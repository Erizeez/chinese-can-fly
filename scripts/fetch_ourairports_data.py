#!/usr/bin/env python3
"""
OurAirports 中国区域机场与跑道数据提取清洗脚本
用于为“中国人能飞” (Chinese Can Fly) 生成全离线机场与跑道元数据库。
"""

import csv
import json
import os
import sys
import urllib.request

AIRPORTS_URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"
RUNWAYS_URL = "https://davidmegginson.github.io/ourairports-data/runways.csv"

def download_file(url, target_path):
    print(f"正在下载: {url} -> {target_path} ...")
    urllib.request.urlretrieve(url, target_path)
    print("下载完成。")

def process_data(data_dir, output_json):
    airports_csv = os.path.join(data_dir, "airports.csv")
    runways_csv = os.path.join(data_dir, "runways.csv")

    if not os.path.exists(airports_csv):
        download_file(AIRPORTS_URL, airports_csv)
    if not os.path.exists(runways_csv):
        download_file(RUNWAYS_URL, runways_csv)

    print("正在提取并关联中国区域 (ISO Country = 'CN') 的机场与跑道信息...")
    airports_map = {}
    
    with open(airports_csv, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("iso_country") == "CN":
                ident = row.get("ident")
                airports_map[ident] = {
                    "ident": ident,
                    "icao": row.get("gps_code") or row.get("ident"),
                    "iata": row.get("iata_code", ""),
                    "name": row.get("name", ""),
                    "municipality": row.get("municipality", ""),
                    "latitude": float(row.get("latitude_deg") or 0.0),
                    "longitude": float(row.get("longitude_deg") or 0.0),
                    "elevation_ft": float(row.get("elevation_ft") or 0.0) if row.get("elevation_ft") else None,
                    "type": row.get("type", ""),
                    "runways": []
                }

    print(f"共提取到 {len(airports_map)} 个中国境内机场。")

    runway_count = 0
    with open(runways_csv, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            airport_ident = row.get("airport_ident")
            if airport_ident in airports_map:
                runway_item = {
                    "id": row.get("id"),
                    "length_ft": float(row.get("length_ft") or 0.0) if row.get("length_ft") else None,
                    "width_ft": float(row.get("width_ft") or 0.0) if row.get("width_ft") else None,
                    "surface": row.get("surface", ""),
                    "lighted": row.get("lighted") == "1",
                    "le_ident": row.get("le_ident", ""),
                    "le_latitude": float(row.get("le_latitude_deg") or 0.0) if row.get("le_latitude_deg") else None,
                    "le_longitude": float(row.get("le_longitude_deg") or 0.0) if row.get("le_longitude_deg") else None,
                    "le_elevation_ft": float(row.get("le_elevation_ft") or 0.0) if row.get("le_elevation_ft") else None,
                    "le_heading_degT": float(row.get("le_heading_degT") or 0.0) if row.get("le_heading_degT") else None,
                    "he_ident": row.get("he_ident", ""),
                    "he_latitude": float(row.get("he_latitude_deg") or 0.0) if row.get("he_latitude_deg") else None,
                    "he_longitude": float(row.get("he_longitude_deg") or 0.0) if row.get("he_longitude_deg") else None,
                    "he_elevation_ft": float(row.get("he_elevation_ft") or 0.0) if row.get("he_elevation_ft") else None,
                    "he_heading_degT": float(row.get("he_heading_degT") or 0.0) if row.get("he_heading_degT") else None,
                }
                airports_map[airport_ident]["runways"].append(runway_item)
                runway_count += 1

    print(f"共关联 {runway_count} 条跑道数据。")

    output_list = list(airports_map.values())
    os.makedirs(os.path.dirname(output_json), exist_ok=True)
    with open(output_json, mode='w', encoding='utf-8') as f:
        json.dump(output_list, f, ensure_ascii=False, indent=2)

    file_size_kb = os.path.getsize(output_json) / 1024
    print(f"成功导出中国离线机场跑道数据库: {output_json} (大小: {file_size_kb:.2f} KB)")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_cache = os.path.join(script_dir, "cache")
    os.makedirs(data_cache, exist_ok=True)
    out_file = os.path.join(script_dir, "..", "CCFlyCore", "Sources", "CCFlyCore", "Resources", "china_airports_runways.json")
    process_data(data_cache, out_file)
