apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ appName }}
  namespace: {{ k8sNamespace }}
spec:
  minReplicas: {{ minReplicas }}
  maxReplicas: {{ maxReplicas }}
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ appName }}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
---
apiVersion: v1
kind: Service
metadata:
  name: {{ appName }}-svc
  namespace: {{ k8sNamespace }}
spec:
  type: ClusterIP
  selector:
    app: {{ appName }}
  ports:
  - name: http
    targetPort: {{ appServerPort }}
    port: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ appName }}
  namespace: {{ k8sNamespace }}
  labels:
    app: {{ appName }}
  annotations:
    kubernetes.io/change-cause: {{ appImage }}:{{ appTag }}
spec:
  selector:
    matchLabels:
      app: {{ appName }}
  strategy:
    rollingUpdate:
      maxUnavailable: 0
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: {{ appName }}
        lang: {{ label_lang }}
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: {{ appName }}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              topologyKey: kubernetes.io/hostname
              labelSelector:
                matchExpressions:
                 - key: app
                   operator: In
                   values:
                   - {{ appName }}
          - weight: 100
            podAffinityTerm:
              topologyKey: topology.kubernetes.io/zone
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - {{ appName }}
      containers:
      - name: {{ appName }}
        image: {{ appImage }}:{{ appTag }}
        ports:
        - containerPort: {{ appServerPort }}
        {% if configMapEnv -%}
        envFrom:
        - configMapRef:
            name: {{ configMapName }}
        {% endif -%}
        {% if secretEnv -%}
        envFrom:
        - secretRef:
            name: {{ secretName }}
        {% endif -%}
        {% if configMapMount -%}
        volumeMounts:
        - name: settings-cm
          mountPath: {{ configMapMountPath }}
          subPath: {{ configMapsubPath }}
          readOnly: true
        {% endif -%}
        {% if secretMount -%}
        volumeMounts:
        - name: settings-secret
          mountPath: {{ secretMountPath }}
          subPath: {{ secretsubPath }}
          readOnly: true
        {% endif -%}
        resources:
          limits:
            cpu: {{ limitCPU }}
            memory: {{ limitMem }}
        startupProbe:
          tcpSocket:
            port: {{ appServerPort }}
          failureThreshold: 30
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: {{ appServerPort }}
          periodSeconds: 10
          failureThreshold: 180
        readinessProbe:
          tcpSocket:
            port: {{ appServerPort }}
          periodSeconds: 10
          failureThreshold: 3
      imagePullSecrets:
      - name: {{ pullImageCredentials }}
      {% if configMapMount -%}
      volumes:
      - name: settings-cm
        configMap:
          name: {{ configMapName }}
      {% endif -%}
      {% if secretMount -%}
      volumes:
      - name: settings-secret
        secret:
          secretName: {{ secretName }}
      {% endif -%}
