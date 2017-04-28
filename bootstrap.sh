#!/bin/bash

set -euo pipefail

MASTER=$1
REMOTE="root@$MASTER"

VERSION=$(ssh $REMOTE "hiera --version")

echo "Remote server is running Hiera $VERSION"

# Classifier terminus
scp classifier.rb $REMOTE:/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/puppet/indirector/node/classifier.rb

# Classifier Hiera backend
scp lib/puppet/functions/classifier_data.rb $REMOTE:/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/puppet/functions/classifier_data.rb

# Test site.pp
scp site.pp $REMOTE:/etc/puppetlabs/code/environments/production/manifests/site.pp

# Hiera config with the Classifier backend enabled
scp hiera.yaml $REMOTE:/etc/puppetlabs/puppet/hiera.yaml

# Restart pe-puppetserver
ssh $REMOTE "systemctl restart pe-puppetserver"
#ssh $REMOTE "kill -HUP `systemctl status pe-puppetserver | grep 'Main PID' | awk '{print $3}'`"

# Run puppet
ssh $REMOTE "puppet agent -t"
