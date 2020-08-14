# Purpose
This pipeline automates the EM SW Installation.

The Pipeline automates process described in:
* EM Baremetal: [EM20 - Platform Installation Manual](https://al4b.cpi.ericsson.net/elex?LI=EN/LZN7059064*&FN=1_1531-FAM901569Uen.*.html) and [EM20 - Software Installation Manual](https://al4b.cpi.ericsson.net/elex?LI=EN/LZN7059064*&FN=3_1531-FAM901569Uen.*.html)
* EM Virtualized: [EM20 - Installation Manual Using OVA Image](https://al4b.cpi.ericsson.net/elex?LI=EN/LZN7059064*&FN=5_1531-FAM901569Uen.*.html)

* Pipeline also provides support for:
   * Fresh Installation in EM Upgrade scenario with New Hardware
   * Installation of Optional Components like DRRF, DRViewer, Custom Report, Reporting Database, ESA
   * Creation of Additional FEM and OLM Logical Servers
   * EM Hardening
   * NTP Configuration
   * Triggering of inmmediate backups with BnRUtility

# Benefits
1. SW Installation is being executed in "1-Click"
2. Multiple hosts can be installed in parallel
3. Follow same WoW in all EMM being installed
4. Supports both Cluster and Standalone deployments
5. Supports Platform, Manager, File and Event Mediation and Online Mediation modules

# Asset Access
Open a request to [SA BSS Service Desk](https://eteamproject.ericsson.net/servicedesk/customer/portal/61).

# Pre-requistes
1. Take **Full Backup** of existing EM System in Upgrade scenario
2. **Enviroment**:
   * If **Native/Baremetal EM**: HW connected, external disks created and exposed, RHEL OS installed, DDS available
   * If **Virtual EM**: VMs deployed from OVA image, external disks created and exposed, DDS available
   * If **Cloud Enviroment**: VMs deployed, NFS external disk created and exposed, DDS available (Not verified yet)
3. Configure **ssh keyless connectivy** between nodes and cps servers
4. **Enviroment details** available: IPs/VIPs, NICs/vNICs, users/password ...
5. **EM SW downloaded** from SWGW and uploaded to Jfrog Artifactory or DDS
6. **Hostnames** should be set before pipeline execution as pipeline is using "hostname".yml to load system variables
7. **sudo user** available for installation, since root is disable in EM20. Same user/pwd in all systems.
8. Update **Disk Names** in ROLES\platform_emm\files\install_updated.sh if DISK I/O Fencing or external storage are used.

# How to execute
1. **Clone/Fork** gitlab project
2. **If Rosetta**: Register gitlab runner in DDS and enable ssh connectiviy from DDS to EM (update known_hosts in EM)
3. **Without Rosetta**: Transfer playbooks manually to DDS and enable ssh connectiviy from DDS to EM (update known_hosts in EM, ...). Also Run dos2unix or similar (sed 's/\r//') to remove the Carriage Return from files.
4. **Update enviroment details** in .yml files (and cp_server_ip file) under ENV_INFO folder and in HOST/hosts file
5. **Execute pipeline** (run jobs only required for your setup), examples:
   * **Standalone Virtualized/Cloud**: uploadsoftwaretoemm, emmplatform, mgrappinstall, mgrhealthcheck, femappinstall, femhealthcheck, olmappinstall, olmhealthcheck emmcreatelogicalservers
   * **Standalone Baremetal**: uploadsoftwaretoemm, mmplatformospatches, emmplatform3pp, cpsplatformveritas, emmplatform, mgrappinstall, mgrhealthcheck, femappinstall, femhealthcheck, olmappinstall, olmhealthcheck emmcreatelogicalservers
   * **Cluster Virtualized with CPS Fencing**: uploadsoftwaretocps, uploadsoftwaretoemm, cpsplatform, cpsplatformhealthcheck, emmplatform, emmmasterhealthcheck, emmaddnode, emmworkerhealthcheck, mgrappinstall, mgrhealthcheck, mgrappaddnode, femappinstall, femhealthcheck, femappaddnode, olmappinstall, olmhealthcheck, olmappaddnode, emmcreatelogicalservers
   * **Cluster Baremetal with CPS Fencing** Fencing: uploadsoftwaretocps, uploadsoftwaretoemm, emmplatformospatches, cpsplatformveritas, cpsplatform, cpsplatformhealthcheck, emmplatformveritas, emmplatform3pp, emmplatform, emmmasterhealthcheck, emmaddnode, emmworkerhealthcheck, mgrappinstall, mgrhealthcheck, mgrappaddnode, femappinstall, femhealthcheck, femappaddnode, olmappinstall, olmhealthcheck, olmappaddnode, emmcreatelogicalservers

# Directory Structure
```
|-- HOST
    |-- hosts: ansible host file
|-- PLAYBOOKS: ansible playbooks
|-- ROLES: ansible roles
    |-- ROLES\platform_emm\files\install_updated.sh: update external disk names
    |-- ...
|-- .gitlab-ci.yml: GitLab CI/CD Pipeline configuration
|-- README.md: this file
|-- ENV_INFO:
    |-- BACKUPS
       |-- *.in: input parameters expected by BnRUtility for immediate backups of the conpoments already configured in BnR.config
       |-- BackupExternalDir.in: list of shared directory/files to backup from master node.
       |-- BackupInternalDir.in: list of directories/files to backup in each node.
    |-- CMP: *.in: input parameters expected by MM_UTILITY for creation of Optional ComPonents: Custom Reports, DRRF, DRViewer, ESA, Reporting Database, Traffic VIPs ...
    |-- DISK
       |-- DG: *.in: input parameters expected by MM_UTILITY for the creation of Disk Groups
       |-- CLUS: *.in: input parametes expected by MM_UTILITY to add a Disk Group to a Cluster Service Group
    |-- LS: *.in: input parameters expected by MM_UTILILY for the creation of additional FEM and OLM Logical Servers
    |-- SH:
        |-- MM_Harden.ini: EM template for hardening
        |-- System_Hardening.in: input parameters required by MM_UTILITY to execute System Hardening
    |-- cp_server_ip: list of CP Server VIPs in case CPS is used as Veritas I/O Fencing
    |-- emm.yml: pipeline parameters +
    |-- mgr.yml: parameters used to install Manager Component
    |-- fem.yml: parameters used to install File & Event Component
    |-- olm.yml: parameters used to install Online Mediation Components
    |-- <hostname>.yml: parameters used to install EM Platform in that particular node.
```

# Challenges
1. Some scripts has been customized from the ones delivered by "SW - Tools" to avoid user interaction
2. If CPS I/O Fencing is used, then update 3 CPS VIPs in "cp_server_ip", this is required to avoid prompt from installation scripts
3. For EM Upgrade scenario, it was NOT possible to automate upgrade_manager.sh, upgrade_fem.sh and upgrade_olm.sh, and disk migration scripts since these scripts are interactive and they are not accepting inputs from "stdin" only from terminal.
4. Automation of Hardening requires Java to be installed, In EM standard installation the CP Servers are not having Java, so EM Hardening playbook will NOT execute Hardening in EMM_CPS nodes. Either configure EM Hardening in CPS Manually, or install java from 3PP and then modify Hardening playbook to execute hardening in CPS as well.

# Stages
**backupdata:** runs in master node to backup shared directories (MMDB, MMStorage …) and to execute immediate backup with bnrUtility
**backuproot:** runs in master and workers to internal directories (/home, /etc ...) and execute to immediate backup of root disk with bnrUtility 
**uploadsoftwaretocps:** uploads SW to CP Servers either from DDS or Jfrog
**uploadsoftwaretoemm:** uploads SW to EM Servers either from DDS or Jfrog
**emmplatformospatches:** performs OS Patches installation in master, workers and cp servers.
**cpsplatformveritas:** performs veritas instalallation in CP servers
**cpsplatform :** This stage will install the CPS platform in 3 CP servers automatically.
**cpsplatformhealthcheck:** This stage will check if the CP servers are running with service group online.
**emmplatformveritas:** performs Veritas installation in master and workers
**emmplatform3pp:** performs 3PP SW installation in master and workers
**emmupgradecreatedg20:** in Fresh Installation for EM Upgrade scenario (-O NODG), creates Disk Groups and their **respective Cluster Service Groups
**emmplatform:** This stage will install emm platform in master server.
**emmmasterhealthcheck:** This stage will check the emm platform is running with service group online.
**emmaddnode:** This stage will join the emm platform in worker node in cluster. 
**emmworkerhealthcheck:** This stage will check the emm worker node is running properly in cluster or not.
**mgrappinstall:** This stage will install the MGR app in master node.
**mgrhealthcheck:** This stage will check the MGR app installed properrly or not with resources are online.
**mgrappaddnode:** This stage will install MGR in worker node for failover scenario.
**femappinstall:** This stage will install the FEM app in master node
**femhealthcheck:** This stage will check the FEM app installed properrly or not with resources are online.
**femappaddnode:** This stage will install FEM in worker node for failover scenario.
**olmappinstall:** This stage will install the OLM app in master node
**olmhealthcheck:** This stage will check the OLM app installed properrly or not with resources are online.
**olmappaddnode:** This stage will install OLM in worker node for failover scenario.
**emmcreatelogicalservers:** creates additional Logical Servers (Server2, SERVER2 …) and Optional Components (DRRF, DRViewer …)
**emmupgradedbapp:** can be use to upgrade additional database (DRRF, DRViewer, Reporting Database, Custom Report)
**ntp:** peforms NTP Configuration
**systemhardening:** performs system hardening with MM_UTILITY in master and workers (not in CPS)
**restoredata:** only for standalone, restores data from backup taken in backupdata stage