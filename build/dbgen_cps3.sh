#!/bin/bash
# Preparing working Directories
sudo -u ec2-user mkdir -p /home/ec2-user/tpch_benchmark/src/bootstrap
sudo -u ec2-user mkdir -p /home/ec2-user/tpch_benchmark/src/client/redshift
sudo -u ec2-user mkdir -p /home/ec2-user/tpch_benchmark/git	

# Installing Python SDK and Redshift Libraries
cd /home/ec2-user/tpch_benchmark/src/client/redshift
sudo -u ec2-user pip-3.6 install boto3 -t .
sudo -u ec2-user pip-3.6 install psycopg2 -t .

# Downloading the official TPC-H DBGen Binaries
cd /home/ec2-user/tpch_benchmark/git
sudo -u ec2-user git clone https://github.com/data-benchmarks/tpch.git
cd /home/ec2-user/tpch_benchmark/git/tpch/v2.18.0
sudo -u ec2-user unzip tpch_2.18.0_rc2.zip -d /home/ec2-user/tpch_benchmark/src/bootstrap/

# Compiling TPC-H Binaries
cd /home/ec2-user/tpch_benchmark/src/bootstrap/tpch_2.18.0_rc2/dbgen
sudo -u ec2-user cp /home/ec2-user/tpch_benchmark/git/tpch/config/makefile.linux makefile
sudo -u ec2-user make

# Mounting EBS Volume            
#    Note: Pending to Remove hard-coded volume name (e.g. nvme1n1). 
sudo mkfs -t ext4 -q /dev/nvme1n1

# Adding sleep, since mkfs can take a few seconds to execute
sudo sleep 15

# Mounting new fs
sudo mkdir /tpch_benchmark
sudo mount /dev/nvme1n1 /tpch_benchmark
mkdir -p /tpch_benchmark/data
sudo chown ec2-user:ec2-user -R /tpch_benchmark/data

# Generating TPC-H Data -- Temporal hard-coding values for testing:           
export DoP=10
export SCALING_FACTOR=${ScalingFactor}        
export DSS_PATH=/tpch_benchmark/data
cd /home/ec2-user/tpch_benchmark/src/bootstrap/tpch_2.18.0_rc2/dbgen
for (( c=1; c<=$DoP; c++ )); do yes 'no' | ./dbgen -v -C $DoP -s $SCALING_FACTOR -S $c & done

# Wait for DBGen to finish
export PROC=1
while [ $PROC -gt 0 ]; do sleep 5; PROC=`pgrep -x "dbgen" | wc -l`; echo "DBGen Processes still running: $PROC"; done
sudo chown ec2-user:ec2-user -R /tpch_benchmark/data

# Moving data files to correct directories
cd /tpch_benchmark/data
mkdir customer lineitem orders partsupp part supplier region nation
for i in customer lineitem orders partsupp part supplier region nation; do mv ./$i.* ./$i/.; done
aws s3 cp --recursive . s3://tpch-lab-reusable-asset/
