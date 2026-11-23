# System Architecture: Automated DevOps Pipeline

## 1. Overview
This project realizes an end-to-end automated infrastructure and service lifecycle for a scalable **URL Shortener Application** using **Terraform**, **Puppet**, and **Nagios Core** on **Amazon Web Services (AWS)**.

```
       +-------------------------------------------------------+
       |                   AWS VPC (10.0.0.0/16)               |
       |                                                       |
       |   +-----------------------------------------------+   |
       |   |             Public Subnet (10.0.1.0/24)       |   |
       |   |                                               |   |
       |   |   +-----------------+   +-----------------+   |   |
       |   |   |  Puppet Master  |   |  Nagios Server  |   |   |
       |   |   |   (10.0.1.10)   |   |   (10.0.1.20)   |   |
       |   |   |  Puppet Server  |   |   Nagios Core   |   |   |
       |   |   +--------+--------+   +--------+--------+   |   |
       |   |            |                     |            |   |
       |   |       Catalog Sync        NRPE & HTTP checks  |   |
       |   |            |                     |            |   |
       |   |            v                     v            |   |
       |   |   +-----------------+   +-----------------+   |   |
       |   |   |      web-1      |   |      web-2      |   |   |
       |   |   |   (10.0.1.31)   |   |   (10.0.1.32)   |   |
       |   |   |  Nginx + Flask  |   |  Nginx + Flask  |   |   |
       |   |   |  URL Shortener  |   |  URL Shortener  |   |   |
       |   |   +-----------------+   +-----------------+   |   |
       |   +-----------------------------------------------+   |
       +-------------------------------------------------------+
```

## 2. Component Roles
1. **Terraform (Provisioning)**:
   - Provisions AWS VPC, Subnet, Internet Gateway, Security Groups, and EC2 instances.
   - Bootstraps each node using `user-data` scripts.
   - Automatically renders Nagios host configuration files dynamically based on instance count.

2. **Puppet (Configuration Management & Self-Healing)**:
   - Central Puppet Master (`10.0.1.10`) serves configuration catalogs.
   - Enforces desired state: Nginx, Python 3, Gunicorn, URL Shortener microservice, and NRPE daemon.
   - Continuously corrects configuration drift (e.g. restoring deleted files or restarting killed services).

3. **Nagios (Continuous Monitoring & Observability)**:
   - Nagios Core server (`10.0.1.20`) with Web UI.
   - Active Checks: ICMP Ping, SSH port 22, HTTP `/health` application endpoint.
   - NRPE Passive/Agent Checks: Disk usage, CPU load average, Gunicorn process, Nginx process.
