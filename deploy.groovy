def createTag() {
      return new Date().format('yyyyMMddHHmmss') + "_${env.BUILD_ID}"
}

pipeline {
  agent any

  options {
    disableConcurrentBuilds()
    timestamps()
  }

  environment {
    appTag =  createTag()
    cfToken = credentials("cloudflaretoken")
    gitlabToken = credentials("gitlabtoken")
    appName = "${env.JOB_BASE_NAME}"
  }

  stages {
    stage("preparation") {
      steps {
        script {
	  sh "rm -rf cisrc && mkdir -p cisrc"
	  load "pipeline/default.env.groovy"
	  load "pipeline/"+env.JOB_BASE_NAME+".env.groovy"

	  //python jinja2 handle template
	  docker.image('python:3.10').inside {
	    sh """
	      export HOME=/tmp
              export PIP_CACHE_DIR=\$HOME/.cache/pip
	      pip3 install --user --no-cache-dir jinja2
	      export PYTHONPATH=\$HOME/.local/lib/python3.*/site-packages:\$PYTHONPATH
	      python3 pipeline/render.py
	    """
	  }


	  //groovy handle template
          //def deployYaml = readFile('pipeline/deploy.yaml.tpl')
	  //def envOutput = sh(script: 'env', returnStdout: true).trim()
	  //def envVars = [:]
          //envOutput.split('\n').each { line ->
          //  def keyValue = line.split('=')
          //  if (keyValue.size() == 2) {
          //    envVars[keyValue[0]] = keyValue[1]
          //  }
          //}
	  //envVars.each { key, value ->
          //	deployYaml = deployYaml.replaceAll("\\\$\\{${key}\\}", value)
          //}
	  //writeFile file: "pipeline/"+env.appName+'-deploy.yaml', text: deployYaml

        }
      }
    }

    stage("gitlabe PullCode") {
      steps {
        script {
	   echo "gitURL: ${gitURL}"
	   echo "gitBranch: ${gitBranch}"
	}
        dir("cisrc") {
          git url: env.gitURL,
          credentialsId: env.gitCredentials,
          branch: env.gitBranch
	}
      }
    }

    stage("docker Build") {
      steps {
        script {
          dir("cisrc") {
	    sh "cp ../pipeline/${env.JOB_BASE_NAME}.dockerfile ./Dockerfile"
            docker.withRegistry(env.harborURL, env.harborCredentials){
              sh """
              docker build --build-arg gitlabToken=${gitlabToken} -t $appImage:$appTag .
              docker push $appImage:$appTag
              docker rmi $appImage:$appTag
              """
	    }
          }
        }
      }
    }

    stage("k8s Deploy") {
      steps {
        script {
	  dir("cisrc") {
	    sh "cp ../pipeline/${env.appName}-deploy.yaml ./deploy.yaml"
            withKubeConfig([serverUrl: env.k8sURL, credentialsId: env.k8sCredentials]) {
              sh """
                kubectl apply -f deploy.yaml
              """
            }
	  }
        }
      }
    }

    stage("cloudflare cachePurge") {
      when {
        expression  { return  env.isCFPurge.toBoolean() }
      }
      steps {
        script {
            sh 'chmod +x ./pipeline/cloudflare.sh && ./pipeline/cloudflare.sh $zoneId $cfToken'
        }
      }
    }

    stage("k8s Rollback") {
      options {
        timeout(time: 12, unit: "HOURS")
      }
      input {
        ok "submit"
        message "Rollback"
        parameters {
          booleanParam(name: 'ROLLBACK', defaultValue: false, description: "If you want rollback, please select.")
        }
      }
      steps {
        script {
          if (ROLLBACK == "true") {
            withKubeConfig([serverUrl: env.k8sURL, credentialsId: env.k8sCredentials]) {
              sh """
                kubectl rollout undo deployment $appName -n $k8sNamespace
              """
            }
          }
        }
      }
    }

  }

  post {
    always {
      script {
        wrap([$class: 'BuildUser']) {
          currentBuild.displayName = "#${BUILD_NUMBER} ${BUILD_USER}"
        }
      }
    }
  }

}
