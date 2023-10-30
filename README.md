# ETL pipeline for unloading bacpac files into MS SQL Server 
Author: David Salac

## Introduction
This document describes creating a virtual machine that works as a Microsoft SQL Server and a related local pipeline (running as a PowerShell script) that unloads BacPac archives into this machine from Azure Storage Account's blob. It also fully describes how to set up networking concerning FlowEHR architecture that uses this VM-based SQL Server as a data source for the bronze/silver/gold data pipeline.

## Prerequisites
You need to have:
 - **FlowEHR instance** running (be aware of what you set as a SQL Server URL when spinning one on). You also need to know the **Core Address Space (CIDR)** of the Virtual Network related to this FlowEHR instance.
 - **Blob (Azure Storage Account)** acting as a landing zone for BacPac files that are supposed to be unpacked.

## How to create a Virtual Machine with Microsoft SQL Server
Click to Create an Azure Virtual Machine. Be aware of the following:
1. As `Image`, select `SQL Server 2017 on Windows Server 2016`, click on `Select` and select `SQL Server 2017 Enterprise Windows Server 2016 - Gen2`. Set the rest as needed (or see below in the summary) - default values are alright.
2. In the `Disk` tab, change the OS disk size to `128 GiB`. Choose `Standard SSD`.
3. In the `Networking` tab, create a new Virtual Network, be aware that core **Address Space** (CIDR) must differ from the FlowEHR's one, but optimally also from the `mric-landing` one. Also, optionally, select `Delete public IP and NIC when VM is deleted`.
4. Leave the `Management`, `Monitoring` and `Advanced` tabs with the default configuration.
5. In the `SQL Server settings` tab, enable `SQL Authentication`.

### Summary of the VM
<details>
<summary>Click to see the whole summary (Review + create dump)</summary>
Basics

Subscription: UKS-MRIC-TRE-Development

Resource group: (new) mric-bacpac-etl

Virtual machine name: vm-mric-bacpac-etl

Region: UK South

Availability options: Availability zone

Availability zone: 1

Security type: Trusted launch virtual machines

Enable secure boot: Yes

Enable vTPM: Yes

Integrity monitoring: No

Image: SQL Server 2017 Enterprise Windows Server 2016 - Gen2

VM architecture: x64

Size: Standard D8ads v5 (8 vcpus, 32 GiB memory)

Username: bacpacadmin

Public inbound ports: RDP

Already have a Windows license?: No

Azure Spot: No

Disks

OS disk size: 128 GiB

OS disk type: Standard SSD LRS

Use managed disks: Yes

Delete OS disk with VM: Enabled

Ephemeral OS disk: No

Networking

Virtual network: (new) vnet-mric-bacpac-etl

Subnet: (new) default (10.7.0.0/24)

Public IP: (new) vm-mric-bacpac-etl-ip

Accelerated networking: On

Place this virtual machine behind an existing load balancing solution?: No

Delete public IP and NIC when VM is deleted: Enabled

Management

Enable Automanage: Off

Configuration profile: None

Microsoft Defender for Cloud: Basic (free)

System assigned managed identity: Off

Login with Azure AD: Off

Auto-shutdown: Off

Site Recovery: Disabled

Enable hotpatch: Off

Patch orchestration options: OS-orchestrated patching: patches will be installed by OS

Monitoring

Alerts: Off

Boot diagnostics: On

Enable OS guest diagnostics: Off

Advanced

Extensions: None

VM applications: None

Cloud init: No

User data: No

Disk controller type: SCSI

Proximity placement group: None

Capacity reservation group: None

SQL Server settings

Warning: Per hour VM price shown above does not include SQL Server License

SQL Server License: Pay As You Go

SQL connectivity level: Private

SQL port: 1433

SQL Authentication: Enabled

SQL Server Machine Learning Services (In-Database): Disabled

SQL Authentication login: bacpacadmin

Storage optimization type: Transactional processing

SQL Data file path: F:\data

SQL Data storage: 1024 GiB, 5000 IOPS, 200 MB/s, Premium SSD

SQL Log file path: G:\log

SQL Log storage: 1024 GiB, 5000 IOPS, 200 MB/s, Premium SSD

SQL TempDb file path: D:\tempDb

SQL TempDb storage: Use local SSD drive

SQL TempDb data file count: 8

SQL TempDb data file size: 8

SQL TempDb data file growth size: 64

SQL TempDb log file size: 8

SQL TempDb log file growth size: 64

Move system DB to data pool disk: false

Automated patching: Enabled

Auto patching schedule: Sunday at 2:00

Automated backup: Disabled

Azure Key Vault integration: Disabled

MAXDOP: 0

Optimize for ad-hoc workload: Disabled

Server Collation: SQL_Latin1_General_CP1_CI_AS

SQL Server memory limits: 0 - 2147483647 MB

Lock pages in memory: Disabled

Instant file initialization: Disabled
</details>

### Important notes:
- Disable the RDP port once you are finished (at least restrict it to some IP ranges).

## Networking
The basic logic of networking:
 - Blob Storage and VM are connected using Service Endpoints.
 - VM and FlowEHR are connected using Peerings (Virtual Network Peering).

**Blob - VM network:** To set up the networking between the blob and VM, go to the blob, select the `Networking` option, and select `Enabled from selected virtual networks and IP addresses`. Then, in the `Virtual networks` section, select `Add existing virtual network` - there you need to find the VM's virtual network and its subnet. **Important: disable all Exceptions!** 

**VM - FlowEHR network:** To set up the networking between the VM and the FlowEHR instance, go to the VM, select the `Networking` option, click on the `Virtual network/subnet` (this gets you into `Virtual network` resource related to VM - you can get there directly from the resource group as well). There, click on `Peerings` and add a new one. There, write some meaningful names for both peering links (e. g. starting with the prefix `peer`, following `peer-SOURCE-TARGET`), then select the `Virtual network` related to FlowEHR instance. The rest should be in default.

## Setting up the VM
The goal is:
 - Install Microsoft Azure Storage Explorer [https://azure.microsoft.com/en-gb/products/storage/storage-explorer](see the Microsoft Azure Storage Explorer tool website here). This is not mandatory, but it makes things much easier as it installs .NET 6 together with the tool that is needed for each of the following tools; it also makes debugging easier.
 - Install **SqlPackage** tool [https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage?view=sql-server-ver16](see the Microsoft SqlPackage tool website here).
 - Install **AzCopy** [https://learn.microsoft.com/en-us/azure/storage/common/storage-ref-azcopy](see the Microsoft AzCopy website here).
 - Set up the **script for unloading bacpac** files.
 - Set up the logic that **calls the script periodically**.

### How do I download things from inside the VM?
In order to download anything inside the VM, you need to have downloading enabled. To do so, go to the `Internet Options` (just search in the Start menu), then select the `Security` tab, click on `Custom level...`, and in the `Downloads` section, enable `File download`. Another option is to pass files through the clipboard.

_Note: try to use the browser as minimally as possible; optimally, just pass the links to download things. When you load a new page, you always need to add it as a trusted website - otherwise, it does not load. This makes the process rather user-friendly. Another option is to download Firefox and continue from it._

### Setting up AzCopy and SqlPackage tools
First, after downloading `AzCopy` and `SqlPackage`, add the directory with unzipped content into the PATH variable (on the system level). To do so, go to `Edit the system environment variables` (find it through the Start menu), click on the `Environment Variables...` button, and in the bottom section (called _System variables_) click on the `Path` variable, then click `Edit`, there click on `New` and add the path to the directory with AzCopy (then repeat the same process for SqlPackage). After you finish, save everything (by clicking OK everywhere). Then open a new PowerShell console and try to run the commands:
```
sqlpackage /help
azcopy --help
```
if everything works, this part is done.

### Setting up the scripts
The script is located in `src/bacpac_unload.ps1` - copy and paste this file into some location (optimally into the new directory). Then, fill in all the required configuration variables at the start of the script. After this part is done, all should work (to run the script, just write `.\bacpac_unload.ps1` from the PowerShell console).

### Setting up the periodic job to run the unloading script
Start the `Task Scheduler` (find it via the Start menu):
1. Click on `Create Basic Task` (in the `Action` menu).
2. Choose the required period (probably `Daily`, shorter might cause problems). And follow the wizard.
3. In `Action`, choose `Start a Program`.
4. Pass the location of the script as input (you can Browse it).
