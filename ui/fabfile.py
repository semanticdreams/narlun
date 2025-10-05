import os
from fabric.api import *
from fabric.contrib.project import rsync_project


env.use_ssh_config = True
env['sudo_prefix'] += '-H '


@task
def deploy_ui(s3_bucket):
    local(
        'aws s3 sync --cache-control \'public,max-age=31556926,immutable\' --exclude index.html'
        f' build/web/ s3://{s3_bucket}')
    local(
        f'aws s3 sync --cache-control \'no-cache\' build/web/ s3://{s3_bucket}')


@task
def build():
    local('flutter build web')
