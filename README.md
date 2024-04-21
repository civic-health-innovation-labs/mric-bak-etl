# ETL pipeline for unloading bak files into MS SQL Server 
Author: David Salac

## Introduction
This document describes creating a virtual machine that works as a Microsoft SQL Server and a related local pipeline (running as a PowerShell script) that unloads Bak archives into this machine from Azure Storage Account's blob. It also fully describes how to set up networking concerning HeifER architecture that uses this VM-based SQL Server as a data source for the bronze/silver/gold data pipeline.

## Prerequisites
You need to have:
 - **HeifER instance** running (be aware of what you set as SQL Server URL when spinning one on). You also need to know the **Core Address Space (CIDR)** of the Virtual Network related to this HeifER instance.
 - **Blob (Azure Storage Account)** acting as a landing zone for bak files that are supposed to be unpacked.

## How to create a Virtual Machine with Microsoft SQL Server
Click to Create an Azure Virtual Machine. Be aware of the following:
1. As `Image`, select `SQL Server 2019 Data Server`, click on `Select` and select `SQL Server 2019 Data Server - Gen1`. Set the rest as needed (or see below in the summary) - default values are alright.
2. In the `Disk` tab, change the OS disk size to `128 GiB`. Choose `Standard SSD`.
3. In the `Networking` tab, create a new Virtual Network, be aware that core **Address Space** (CIDR) must differ from the HeifER's one, but optimally also from the `mric-landing` one. Also, optionally, select `Delete public IP and NIC when VM is deleted`.
4. Leave the `Management`, `Monitoring` and `Advanced` tabs with the default configuration.
5. In the `SQL Server settings` tab, enable `SQL Authentication`.


### Important notes:
- Disable the RDP port once you are finished (at least restrict it to some IP ranges).

## Networking
The basic logic of networking:
 - Blob Storage and VM are connected using Service Endpoints.
 - VM and HeifER are connected using Peerings (Virtual Network Peering).
 - Open outbound port 1433 on the VM's Virtual Network (for any connection).
 - Make the private IP address static and use it as an endpoint for SQL connection.

**Blob - VM network:** To set up the networking between the blob and VM, go to the blob, select the `Networking` option, and select `Enabled from selected virtual networks and IP addresses`. Then, in the `Virtual networks` section, select `Add existing virtual network` - there you need to find the VM's virtual network and its subnet. **Important: disable all Exceptions!** 

**VM - HeifER network:** To set up the networking between the VM and the HeifER instance, go to the VM, select the `Networking` option, click on the `Virtual network/subnet` (this gets you into `Virtual network` resource related to VM - you can get there directly from the resource group as well). There, click on `Peerings` and add a new one. There, write some meaningful names for both peering links (e. g. starting with the prefix `peer`, following `peer-SOURCE-TARGET`), then select the `Virtual network` related to HeifER instance. The rest should be in default. Then go to the HeifER resource group, find the Virtual Network resource and do the same process in the opposite direction.

**Opening outbound port 1433 on the VM's Virtual Network:** Go to the VM resource, click on Networking, go to the _Outbound port rules_ tab. Add a rule with `Any` source, source port `*`, destination `Any`, service `MS SQL`; choose a meaningful name and leave the rest as is.

**Making the private IP address static**: go to VM's network interface, click on the IP Configuration, click on the IP and change Allocation to Static.

## Setting up the VM
The goal is:
 - Install Microsoft Azure Storage Explorer [see the Microsoft Azure Storage Explorer tool website here](https://azure.microsoft.com/en-gb/products/storage/storage-explorer). This is not mandatory, but it makes things much easier as it installs .NET 6 together with the tool that is needed for each of the following tools; it also makes debugging easier.
 - Install **AzCopy** [see the Microsoft AzCopy website here](https://learn.microsoft.com/en-us/azure/storage/common/storage-ref-azcopy).
 - Set up the logic that **calls the script periodically**.
 - Install **7-Zip** [see the 7-Zip website here](https://www.7-zip.org/).
 - Set up the logic that **calls the script periodically**.

### How do I download things from inside the VM?
In order to download anything inside the VM, you need to have downloading enabled. To do so, go to the `Internet Options` (just search in the Start menu), then select the `Security` tab, click on `Custom level...`, and in the `Downloads` section, enable `File download`. Another option is to pass files through the clipboard.

_Note: try to use the browser as minimally as possible; optimally, just pass the links to download things. When you load a new page, you always need to add it as a trusted website - otherwise, it does not load. This makes the process rather user-friendly. Another option is to download Firefox and continue from it._

### Setting up AzCopy and 7-Zip tools
First, after downloading `AzCopy`, add the directory with unzipped content into the PATH variable (on the system level). To do so, go to `Edit the system environment variables` (find it through the Start menu), click on the `Environment Variables...` button, and in the bottom section (called _System variables_) click on the `Path` variable, then click `Edit`, there click on `New` and add the path to the directory with AzCopy (then repeat the same process for SqlPackage). After you finish, save everything (by clicking OK everywhere). Then open a new PowerShell console and try to run the commands:
```
azcopy --help
7z --help
```
if everything works, this part is done.

### Setting up the scripts
The script is located in `src/bak_unload.ps1` - copy and paste this file into some location (optimally into the new directory). Then, fill in all the required configuration variables at the start of the script. After this part is done, all should work (to run the script, just write `.\bak_unload.ps1` from the PowerShell console).

### Setting up the periodic job to run the unloading script
Start the `Task Scheduler` (find it via the Start menu):
1. Click on `Create Basic Task` (in the `Action` menu).
2. Choose the required period (probably `Daily`, shorter might cause problems). And follow the wizard.
3. In `Action`, choose `Start a Program`.
4. As `Program`, write `powershell`, and as `Add argument` write `-File LOCATION_OF_PS1_SCRIPT_FILE` - and fill the location of the script instead of `LOCATION_OF_PS1_SCRIPT_FILE`.
