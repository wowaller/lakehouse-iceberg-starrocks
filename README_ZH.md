# StarRocks 与 GCP BigLake Iceberg REST Catalog 集成

本项目包含用于在 Google Compute Engine (GCE) 虚拟机上自动部署单节点 StarRocks (v3.5.19) 集群，并验证其与 Google Cloud BigLake Iceberg REST Catalog 集成情况的脚本。

## 架构

本方案将 StarRocks (FE 和 BE) 部署在安全且私有的 VPC 子网中的单个虚拟机上。
*   **元数据访问 (Metadata Access)**: StarRocks FE 连接到 BigLake Iceberg REST Catalog API (`https://biglake.googleapis.com/iceberg/v1/restcatalog`) 来获取 Schema 和表元数据。
*   **数据访问 (Data Access)**: StarRocks BE 使用虚拟机的 Google 服务帐号 (实例角色 Instance Role) 直接从 Google Cloud Storage (GCS) 读取底层的 Iceberg 数据文件。

```
+-------------------------------------------------------------+
| GCE 虚拟机 (starrocks-test-vm)                              |
|  +------------------+             +------------------+      |
|  |   StarRocks FE   |             |   StarRocks BE   |      |
|  +--------+---------+             +--------+---------+      |
+-----------|--------------------------------|----------------+
            | (REST 元数据 API)              | (GCS 数据读取)
            v                                v
+---------------------------+     +---------------------------+
|    GCP BigLake 元数据服务  |     |     Google Cloud Storage  |
|    (Iceberg REST Catalog) |     |  (gs://binggang-lab-...)  |
+---------------------------+     +---------------------------+
```

## 目录结构

*   `create_sr_vm.sh`: 用于在指定的 GCP 项目和 VPC 子网中创建 GCE 虚拟机的脚本。
*   `setup_sr_inside_vm.sh`: 在虚拟机内部执行的部署脚本（安装 Java、下载 StarRocks、配置 FE/BE 并注册 Backend）。
*   `deploy_sr.sh`: 宿主机编排脚本，负责创建虚拟机、复制安装脚本并在虚拟机上运行。
*   `test_catalog.sh`: 在虚拟机内部运行的测试脚本，用于获取 GCP OAuth2 访问令牌、创建外部 Catalog 并查询测试表。
*   `run_test.sh`: 宿主机辅助脚本，用于将 `test_catalog.sh` 复制到虚拟机并运行。

## 前提条件

1.  **Google Cloud SDK (gcloud)**: 必须在您的本地工作站上安装并完成身份验证。
2.  **VPC 网络**: 在 `us-central1` 区域中已存在一个 VPC 网络（默认：`local-lab`）和子网（默认：`local-lab-us`）。
3.  **Cloud NAT**: 私有子网必须配置 Cloud NAT，以便虚拟机可以在没有公网 IP 的情况下从互联网下载软件包和 StarRocks 压缩包。
4.  **BigLake Catalog**: 一个已存在的 BigLake Iceberg Catalog（默认：`binggang-lab-lakehouse`），其中包含一张表（默认：`sentiment_analysis.sentiment_summary`）。
5.  **权限**: 虚拟机的默认计算引擎服务帐号 (`<project-number>-compute@developer.gserviceaccount.com`) 必须拥有以下角色：
    *   `roles/biglake.admin`（或 `roles/biglake.viewer`）
    *   `roles/storage.admin`（或对 GCS 存储桶的读写权限）

## 配置

您可以通过编辑宿主机脚本顶部的变量来配置项目 ID、区域、子网和虚拟机名称：
*   [deploy_sr.sh](deploy_sr.sh)
*   [create_sr_vm.sh](create_sr_vm.sh)
*   [run_test.sh](run_test.sh)

Catalog 详细信息、GCS 存储桶和查询参数可以在 [test_catalog.sh](test_catalog.sh) 中进行配置。

## 使用方法

### 1. 部署 StarRocks
在您的本地工作站运行部署脚本：
```bash
bash deploy_sr.sh
```
该脚本将执行以下操作：
1.  在 `us-central1-b` 区域创建 GCE 虚拟机 `starrocks-test-vm`。
2.  等待 SSH 连接就绪。
3.  将 `setup_sr_inside_vm.sh` 复制到虚拟机中并运行。
4.  下载 StarRocks 3.5.19，进行配置，启动 FE/BE，并将它们进行绑定注册。

### 2. 运行 Catalog 集成测试
在您的工作站运行测试脚本：
```bash
bash run_test.sh
```
该脚本将执行以下操作：
1.  将 `test_catalog.sh` 复制到虚拟机。
2.  在虚拟机中执行它，该测试脚本将：
    *   获取本地 GCP 服务帐号的访问令牌 (Access Token)。
    *   使用该令牌在 StarRocks 中创建名为 `bq_iceberg` 的外部 Catalog。
    *   列出该 Catalog 中的数据库和表。
    *   查询 `sentiment_analysis.sentiment_summary` 表的前 5 行数据。

## 身份验证选项

在连接 StarRocks 与 BigLake REST Catalog 时，您有两种身份验证方式：

### 方式 1：通过 GoogleAuthManager 自动进行 OAuth2 认证（推荐）
此方法使用 Google Cloud SDK 的应用默认凭据 (ADC) 自动获取并循环更新访问令牌。这是最健壮的方案，可以防止查询因令牌过期而失败。

这需要将 `iceberg-gcp-1.10.0.jar` 和 `iceberg-gcp-bundle-1.10.0.jar` 复制到 StarRocks FE 的 `fe/lib/` 目录下。

```sql
CREATE EXTERNAL CATALOG bq_iceberg
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "uri" = "https://biglake.googleapis.com/iceberg/v1/restcatalog",
    "warehouse" = "gs://binggang-lab-lakehouse",
    "gcp.gcs.use_instance_role" = "true",
    "io-impl" = "org.apache.iceberg.gcp.gcs.GCSFileIO",
    "rest.auth.type" = "org.apache.iceberg.gcp.auth.GoogleAuthManager",
    "header.x-goog-user-project" = "binggang-lab"
);
```

---

## 配置现有 StarRocks 集群

如果您已经有一个运行中的 StarRocks 集群（v3.1.x 或更高版本），并且想要将其连接到 GCP BigLake Iceberg REST Catalog，请按照以下步骤操作：

### 步骤 1：在 StarRocks BE 节点上启用 JNI
Iceberg 集成需要 Java 本地接口 (JNI) 才能在 BE C++ 进程中加载 Iceberg Java 依赖库。
1.  确保所有 BE 实例上均已安装 JDK（JDK 8、11 或 17）。
2.  修改每个 BE 节点上的 BE 配置文件 `be/conf/be.conf`，设置 `JAVA_HOME` 属性：
    ```properties
    JAVA_HOME = /usr/lib/jvm/default-java
    ```
    *（请将 `/usr/lib/jvm/default-java` 替换为您 JDK 的实际安装路径）*。
3.  重启所有 BE 服务以使配置生效：
    ```bash
    ./be/bin/stop_be.sh
    ./be/bin/start_be.sh --daemon
    ```

### 步骤 2：安装 GCP Iceberg 依赖包（推荐，自动认证所需）
如果您希望 StarRocks 通过 `GoogleAuthManager` 自动管理令牌生命周期（方式 1）：
1.  下载 `iceberg-gcp` 和 `iceberg-gcp-bundle` 的 jar 包（使用 `GoogleAuthManager` 需要 `1.10.0` 或更高版本）。
    ```bash
    wget https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp/1.10.0/iceberg-gcp-1.10.0.jar
    wget https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp-bundle/1.10.0/iceberg-gcp-bundle-1.10.0.jar
    ```
2.  将这两个 jar 包复制到您所有 StarRocks Frontend (FE) 实例的 `fe/lib/` 目录下。
3.  重启所有 FE 服务：
    ```bash
    ./fe/bin/stop_fe.sh
    ./fe/bin/start_fe.sh --daemon
    ```

### 步骤 3：授予 StarRocks BE 实例 IAM 权限
StarRocks BE 节点需要访问 GCS 上的数据文件。
*   **使用实例角色 (推荐)**:
    1.  找到您 GCE 虚拟机上挂载的服务帐号。
    2.  在包含 Iceberg 数据的 GCS 存储桶上，授予该服务帐号 **Storage Object Viewer**（或 **Storage Admin**）角色。
*   **使用服务帐号密钥文件**:
    *   创建一个 GCP 服务帐号，下载其 JSON 密钥文件，复制到 StarRocks 节点，并在 Catalog 属性中进行引用（使用 `gcp.gcs.credential.file.path` 属性）。

### 步骤 4：在 StarRocks 中创建外部 Catalog
使用 MySQL 客户端连接到 StarRocks，然后运行对应您所选身份验证方法的 DDL：

#### 使用自动认证创建 (方式 1，推荐)
```sql
CREATE EXTERNAL CATALOG biglake_iceberg
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "uri" = "https://biglake.googleapis.com/iceberg/v1/restcatalog",
    "warehouse" = "gs://<your-gcs-bucket-name>",
    "gcp.gcs.use_instance_role" = "true",
    "io-impl" = "org.apache.iceberg.gcp.gcs.GCSFileIO",
    "rest.auth.type" = "org.apache.iceberg.gcp.auth.GoogleAuthManager",
    "header.x-goog-user-project" = "<your-gcp-project-id>"
);
```
替换：
*   `<your-gcs-bucket-name>`: 包含您 Iceberg 表的 GCS 存储桶名称。
*   `<your-gcp-project-id>`: 您的 GCP 项目 ID（用于计费的项目 Header）。

### 步骤 5：验证连接情况
运行基础查询进行验证：
```sql
SHOW DATABASES FROM biglake_iceberg;
USE biglake_iceberg.<your-database-name>;
SHOW TABLES;
SELECT * FROM <your-table-name> LIMIT 10;
```

---

## 过时 / 替代方法

### 手动令牌认证 (方式 2)
如果您无法将 `iceberg-gcp` 的相关 jar 包添加到类路径中以使用 `GoogleAuthManager`，您可以退而求其次使用手动令牌认证。

#### 设置步骤：
1.  **获取 GCP 访问令牌**: 从元数据服务器或通过 `gcloud` 获取临时 Token：
    ```bash
    TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    ```
2.  **在 StarRocks 中创建 Catalog**: 通过将令牌作为 `header.Authorization` 传递，从而绕过标准的 JWT 令牌解析：
    ```sql
    CREATE EXTERNAL CATALOG biglake_iceberg
    PROPERTIES (
        "type" = "iceberg",
        "iceberg.catalog.type" = "rest",
        "uri" = "https://biglake.googleapis.com/iceberg/v1/restcatalog",
        "warehouse" = "gs://<your-gcs-bucket-name>",
        "gcp.gcs.use_instance_role" = "true",
        "header.Authorization" = "Bearer <GCP_ACCESS_TOKEN>"
    );
    ```
3.  **处理令牌过期**: 访问令牌将在 1 小时后过期，届时查询将失败。您必须使用 `ALTER CATALOG` 更新令牌：
    ```sql
    ALTER CATALOG biglake_iceberg SET PROPERTIES (
        "header.Authorization" = "Bearer <NEW_GCP_ACCESS_TOKEN>"
    );
    ```

---

## 资源清理

若要删除虚拟机并清理 GCE 相关资源，请运行：
```bash
gcloud compute instances delete starrocks-test-vm --zone=us-central1-b --project=binggang-lab
```
