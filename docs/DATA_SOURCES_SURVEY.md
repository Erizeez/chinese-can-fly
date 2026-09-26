# 航空数据源与离线地理信息调研报告 (Data Sources Survey)

本报告针对“中国人能飞”项目所需的四类核心数据：**机场与跑道信息**、**航班动态与航线信息**、**离线省份与地理要素**、**外部极客 ADS-B 数据** 进行全景调研与选型评估。

---

## 一、 机场与跑道信息数据源调研

### 1. OurAirports 开源航空数据库 (首选推荐)
- **授权协议**：Public Domain (CC0，完全商业友好，零版权风险)
- **更新频率**：每晚或每周全量自动构建
- **覆盖范围**：全球 75,000+ 机场，中国境内包含所有大型民航运输机场（ZBAA/PEK, ZGGG/CAN, ZSPD/PVG 等）以及通航机场与军民合用机场。
- **数据结构与关键字段**：
  - `airports.csv`：
    - `ident` / `icao_code` / `iata_code`：ICAO 4字码与 IATA 3字码
    - `name`：中英文机场名称
    - `latitude_deg`, `longitude_deg`：机场基准点经纬度
    - `elevation_ft`：机场标高（海平面高度）
    - `iso_region`：省份代号（如 `CN-11` 北京, `CN-31` 上海, `CN-44` 广东）
  - `runways.csv`：
    - `airport_ident`：关联机场
    - `length_ft`, `width_ft`：跑道长宽（英尺）
    - `surface`：道面材质（ASP 沥青, CON 混凝土）
    - `le_ident`, `he_ident`：跑道低/高端编号（如 `36L` 与 `18R`）
    - `le_latitude_deg`, `le_longitude_deg`, `le_elevation_ft`：跑道低端起始阈值经纬度与标高
    - `le_heading_degT`：跑道真航向角（对正跑道进近与仪表着陆模拟不可或缺）
    - `he_latitude_deg`, `he_longitude_deg`, `he_elevation_ft`, `he_heading_degT`：高端参数
- **本地化集成策略**：
  - 预先运行数据清洗脚本，仅提取 `iso_country = 'CN'`（或东亚常用区域）。
  - 清洗后生成不到 500KB 的精炼 SQLite 或 JSON 离线包，内置进 App Bundle，用户首次启动即可零流量使用。

### 2. OpenStreetMap (OSM) 航空要素提取 (跑道物理轮廓首选)
- **授权协议**：ODbL 开源协议
- **数据深度**：OurAirports 提供的是跑道中心线与两端阈值点，而 OSM 拥有跑道的**真实多边形几何面（Polygons）**、滑行道线条（Taxiway lines）与机位点（Parking stands）。
- **提取方式**：
  - 通过 Overpass API 过滤规则提取中国范围内的机场轮廓：
    ```overpass
    [out:json][timeout:90];
    area["ISO3166-1"="CN"][admin_level=2]->.china;
    (
      way["aeroway"="runway"](area.china);
      way["aeroway"="taxiway"](area.china);
      way["aeroway"="apron"](area.china);
      relation["aeroway"="runway"](area.china);
    );
    out body;
    >;
    out skel qt;
    ```
  - 将提取结果转为 GeoJSON，再通过 `tippecanoe` 制作成仅 2~3MB 的跑道矢量切片（Vector Tiles / MBTiles），叠加在离线地图上可完美呈现跑道宽度与真实走向。

---

## 二、 航班数据可行来源调研

| 数据源类型 | 代表服务 | 优点 | 缺点 / 限制 | 适配场景 |
| :--- | :--- | :--- | :--- | :--- |
| **全离线静态航线库** | 自建 SQLite 静态库 | 100% 离线、零流量、毫秒级响应、输入航班号即出机型与起降点 | 无法获得实时晚点、当前空中位置 | **飞行模式客舱内（核心基础兜底）** |
| **开源学术/开放网络** | **OpenSky Network** (REST API) | 免费开放、无商业封锁、支持中国空域、字段丰富（含 24 维状态向量） | 免费版有频次限制（约 10秒/次），地面偏远区域接收站较少 | **登机前/降落后在线态势感知** |
| **无过滤极客网络** | **ADS-B Exchange** (RapidAPI) | 真实未经修饰的 ADS-B 报文，含军机/公务机 | 商业 API 需付费订阅 | **极客选配** |
| **商业航空 API** | **FlightAware AeroAPI** / **AviationStack** | 全球商业航班时刻表、登机口、行李转盘准确度极高 | 免费额度低，需绑定信用卡 | **商业化拓展阶段** |
| **便携式硬件接收机** | **Stratux / Dump1090 (SDR)** | 真正的物理级独立接收机，直接监听 1090MHz ADS-B 广播，不依赖任何地面基站与互联网 | 需用户自备几十块钱的便携 SDR 硬件通过 WiFi 连手机 | **高阶极客终极玩法** |

### 推荐落地架构：
1. **基础模式**：内置全国 5000+ 热门航班静态数据库（航班号 -> 出发机场、到达机场、标准计划时间、执飞机型参考）。用户输入 `MU5101` 立即展现上海虹桥(SHA)至北京首都(PEK)大圆航线。
2. **在线模式**：有网络时，一键调取 OpenSky Network 或公共 API，刷新该航班的前序状态、预计起飞时间与实时空域高度。
3. **极客局域网模式**：支持输入本地 WiFi 接收机地址（如 `http://192.168.10.1/dump1090/data/aircraft.json`），实时绘制机舱外方圆 100 海里内的真实航空器。

---

## 三、 离线地图（省份、地区边界）信息调研

1. **自然地球 (Natural Earth Data)**：
   - 官方公开无版权限制矢量数据集（`ne_10m_admin_1_states_provinces`）。
   - 包含中国各省、直辖市、自治区边界多边形。
   - 矢量经简化后整体仅约 3~5MB，可直接内嵌在应用中作为离线省份多边形。
2. **天地图 / 标准地图服务矢量规范对照**：
   - 涉及中国地图展示时，严格遵守国家测绘地理信息标准，采用官方规范审图底图与标准十段线表达。
3. **MapLibre 离线切片方案**：
   - 采用标准 MBTiles 格式或新一代 PMTiles 格式。
   - 离线包内仅保留：省市边界、水系、主要山脉高度、机场跑道。不包含冗余建筑物与商铺，实现全国底图压缩至 50MB 以内，支持用户一键下载离线包。
