#!/usr/bin/env python3

import jinja2
import os

with open("pipeline/deploy.yaml.tpl") as fd:
    template = fd.read()

env_vars = dict(os.environ)

rendered = jinja2.Template(template).render(env_vars)

with open('pipeline/'+env_vars["appName"]+"-deploy.yaml", "w") as output:
    output.write(rendered)
