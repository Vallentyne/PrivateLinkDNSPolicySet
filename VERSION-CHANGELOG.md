# Private DNS Policy Set - Version Changelog

## v3 (January 19, 2026) - Enhanced Coverage

**Total Policies: 54** (20 built-in + 34 custom)

### Added in v3:
- ✅ **Azure Batch** - 4 configurations (canadacentral + canadaeast)
  - `Microsoft.Batch/batchAccounts` [batchAccount] - privatelink.[region].batch.azure.com
  - `Microsoft.Batch/batchAccounts` [nodeManagement] - [region].service.batch.azure.com

### Complete Service Coverage:

#### Infrastructure & Compute (6)
- ✅ Azure Kubernetes Service (AKS) - Regional (canadacentral, canadaeast)
- ✅ Azure Batch - Regional (canadacentral, canadaeast) **NEW in v3**
- ✅ Container Registry
- ✅ Compute Disk Access
- ✅ Virtual Machines (via Storage)
- ✅ Azure App Service / Web Apps

#### Storage (19 configurations)
- ✅ Storage Accounts - All endpoints (blob, file, queue, table, dfs, web) + secondary
- ✅ Azure Files Sync Service
- ✅ Recovery Services (Backup + Site Recovery) - Regional

#### Data & Analytics (11)
- ✅ Azure SQL Database
- ✅ Azure Synapse (Sql, SqlOnDemand, Dev)
- ✅ Synapse Private Link Hubs
- ✅ Cosmos DB - All APIs (SQL, MongoDB, Cassandra, Gremlin, Table)
- ✅ Cosmos DB MongoDB vCore
- ✅ PostgreSQL
- ✅ MySQL (Single Server + Flexible Server)
- ✅ MariaDB
- ✅ Data Factory

#### AI & ML (3)
- ✅ **Azure AI Foundry (Cognitive Services)** - 3 DNS zones (cognitiveservices, openai, services.ai)
- ✅ Machine Learning workspaces - 2 DNS zones (api, notebooks)

#### Messaging & Events (5)
- ✅ Event Hub
- ✅ Service Bus
- ✅ Event Grid (topics + domains)
- ✅ SignalR

#### Security & Identity (2)
- ✅ Key Vault
- ✅ Automation Accounts (Webhook + DSCAndHybridWorker)

#### Cache & Search (3)
- ✅ Redis Cache (standard)
- ✅ Redis Enterprise
- ✅ Azure Cognitive Search

#### IoT & Specialized (4)
- ✅ IoT Hub
- ✅ IoT Central
- ✅ Device Update
- ✅ Healthcare APIs (FHIR)

### Key Advantages Over Microsoft Built-In:

1. **Multi-Zone Support**
   - Azure AI Foundry: 3 zones vs Microsoft's 1 zone
   - Machine Learning: 2 zones (api + notebooks)

2. **Additional Services**
   - Redis Enterprise
   - MongoDB vCore
   - MySQL Flexible Server (separate from Single Server)
   - Healthcare APIs (FHIR)

3. **Regional Specificity**
   - AKS zones per region (canadacentral, canadaeast)
   - Backup zones per region (cnc, cne)
   - Batch zones per region

4. **Comprehensive Storage**
   - Primary + Secondary endpoints for all storage types

5. **Policy Versioning**
   - Clean version control via policyVersion parameter
   - No deletion required for updates

---

## v2 (January 9, 2026)

**Total Policies: 50** (20 built-in + 30 custom)

### Changes:
- Added policyVersion parameter for version control
- Deployed to SLZ management group
- First working multi-zone solution for AI Foundry

---

## v1 (December 15, 2025)

**Total Policies: 50** (20 built-in + 30 custom)

### Initial Release:
- Custom policy template with multi-zone support
- Fixed Azure AI Foundry DNS zone creation issue
- Hybrid approach: built-in + custom policies
- Deployed to SLZ management group

### Problem Solved:
Microsoft's built-in Cognitive Services policy only creates 1 DNS zone, breaking Azure AI Foundry which requires 3 zones simultaneously.
