#   (c) Copyright 2019 EntIT Software LLC, a Micro Focus company, L.P.
#   All rights reserved. This program and the accompanying materials
#   are made available under the terms of the Apache License v2.0 which accompany this distribution.
#
#   The Apache License is available at
#   http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
########################################################################################################################
#!!
#! @description: Sets up a simple Marathon infrastructure on one host.
#!
#! @input host: Docker host
#! @input username: username for Docker host
#! @input private_key_file: private key file used for host
#! @input marathon_port: Optional - Marathon agent port - Default: 8080
#! @input timeout: Optional - time in milliseconds to wait for one SSH command to complete - Default: 3000000 ms (50 min)
#!
#! @result SUCCESS: setup succeeded
#! @result CLEAR_CONTAINERS_ON_HOST_PROBLEM: setup failed due to problem clearing containers
#! @result START_ZOOKEEPER_PROBLEM: setup failed due to problem starting zookeeper
#! @result START_MESOS_MASTER_PROBLEM: setup failed due to problem starting Mesos master
#! @result START_MESOS_SLAVE_PROBLEM: setup failed due to problem starting Mesos slave
#! @result START_MARATHON_PROBLEM: setup failed due to problem starting Marathon
#!!#
########################################################################################################################

namespace: io.cloudslang.marathon

imports:
  containers: io.cloudslang.docker.containers

flow:
  name: setup_marathon_docker_host
  inputs:
    - host
    - username
    - private_key_file
    - marathon_port: "8080"
    - timeout: "3000000"

  workflow:
    - clear_containers_on_host:
       do:
         containers.clear_containers:
           - docker_host: ${host}
           - docker_username: ${username}
           - private_key_file
       navigate:
         - SUCCESS: start_zookeeper
         - FAILURE: CLEAR_CONTAINERS_ON_HOST_PROBLEM

    - start_zookeeper:
       do:
         containers.run_container:
           - container_name: "zookeeper"
           - container_params: >
              ${'-p 2181:218 ' +
              '-p 2888:2888 ' +
              '-p 3888:3888'}
           - image_name: "jplock/zookeeper"
           - host
           - username
           - private_key_file
           - timeout
       navigate:
         - SUCCESS: start_mesos_master
         - FAILURE: START_ZOOKEEPER_PROBLEM

    - start_mesos_master:
       do:
         containers.run_container:
           - container_name: "mesos"
           - container_params: >
              ${'--link zookeeper:zookeeper ' +
              '-e MESOS_QUORUM=1 ' +
              '-e MESOS_LOG_DIR=/var/log ' +
              '-e MESOS_WORK_DIR=/tmp ' +
              '-e MESOS_ZK=zk://zookeeper:2181/mesos ' +
              '-p 5050:5050'}
           - image_name: "redjack/mesos-master"
           - host
           - username
           - private_key_file
           - timeout
       navigate:
         - SUCCESS: start_mesos_slave
         - FAILURE: START_MESOS_MASTER_PROBLEM

    - start_mesos_slave:
       do:
         containers.run_container:
           - container_params: >
              ${'--privileged=true ' +
              '--link zookeeper:zookeeper ' +
              '-e MESOS_LOG_DIR=/var/log ' +
              '-e MESOS_MASTER=zk://zookeeper:2181/mesos ' +
              '-e MESOS_CONTAINERIZERS=mesos ' +
              '-p 5051:5051 ' +
              '-v $(which docker):$(which docker) ' +
              '-v /var/run/docker.sock:/var/run/docker.sock'}
           - image_name: "razic/mesos-slave"
           - host
           - username
           - private_key_file
           - timeout
       navigate:
         - SUCCESS: start_marathon
         - FAILURE: START_MESOS_SLAVE_PROBLEM

    - start_marathon:
       do:
         containers.run_container:
           - container_name: "marathon "
           - container_params: >
              ${'--link zookeeper:zookeeper ' +
              '--link mesos:mesos ' +
              '-p ' + marathon_port + ':8080'}
           - container_command: >
              ${'--master mesos:5050 ' +
              '--zk zk://zookeeper:2181/marathon'}
           - image_name: "superguenter/marathon"
           - host
           - username
           - private_key_file
           - timeout
       navigate:
         - SUCCESS: SUCCESS
         - FAILURE: START_MARATHON_PROBLEM

  results:
    - SUCCESS
    - CLEAR_CONTAINERS_ON_HOST_PROBLEM
    - START_ZOOKEEPER_PROBLEM
    - START_MESOS_MASTER_PROBLEM
    - START_MESOS_SLAVE_PROBLEM
    - START_MARATHON_PROBLEM