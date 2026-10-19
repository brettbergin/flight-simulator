"""Reviewed terrain-tools-v1 values; no resolver or caller pin overrides."""

EXPECTED_LOCK = {
    "schema_version": 1, "lock_id": "terrain-tools-v1", "scope": "offline-authoring-only", "runtime_dependency": False,
    "host": {
        "os": "windows", "architecture": "x86_64", "implementation": "cpython", "python_version": "3.12.14",
        "python_executable_bytes": 107312,
        "python_executable_sha256": "d41bad46673f64e0d02f23797f53f90ccf60f27d6eda8d86dd2d4bbeae5a858c",
        "python312_dll_sha256": "8bb70bceffd5877733a957b31c392ca027bd2f84230e00de1654f994422fa2af",
        "python_license_sha256": "886a0ead2d89030ee62dbff52b04e47ab91998341295bb9c56fb952b4e081c7a",
        "frozen_runtime_manifest_sha256": "c29e5f964803bdaa81cf835ee47493cc50cc84712b4a13512f69c9fbfa62c8f7",
        "interpreter_source": "existing-retained-local-runtime-with-raw-file-manifest", "upstream_interpreter_archive": None,
        "wheel_python_tag": "cp312", "wheel_abi_tag": "cp312", "wheel_platform_tag": "win_amd64",
        "executable_selection": "explicit-caller-path-record-and-hash-before-use",
    },
    "wheels": [
        {"name": "pyproj", "version": "3.7.2", "filename": "pyproj-3.7.2-cp312-cp312-win_amd64.whl",
         "url": "https://files.pythonhosted.org/packages/4a/a6/6fe724b72b70f2b00152d77282e14964d60ab092ec225e67c196c9b463e5/pyproj-3.7.2-cp312-cp312-win_amd64.whl",
         "sha256": "11614a054cd86a2ed968a657d00987a86eeb91fdcbd9ad3310478685dc14a128", "bytes": 6312176,
         "python_runtime_dependencies": ["certifi==2025.8.3"], "package_license": "MIT", "identity_evidence": "actual-acquired-bytes-and-pypi-metadata"},
        {"name": "pillow", "version": "12.3.0", "filename": "pillow-12.3.0-cp312-cp312-win_amd64.whl",
         "url": "https://files.pythonhosted.org/packages/45/89/da2f7971a317f83d807fdd4065c0af40208e59e692cc43d315a71a0e96d1/pillow-12.3.0-cp312-cp312-win_amd64.whl",
         "sha256": "a2b55dd6b2a4c4b7d87ffa56bdb33fdc5fdb9a462173861a7bc097f17d91cb09", "bytes": 7227137,
         "python_runtime_dependencies": [], "package_license": "MIT-CMU", "identity_evidence": "actual-acquired-bytes-and-pypi-metadata"},
        {"name": "certifi", "version": "2025.8.3", "filename": "certifi-2025.8.3-py3-none-any.whl",
         "url": "https://files.pythonhosted.org/packages/e5/48/1549795ba7742c948d2ad169c1c8cdbae65bc450d6cd753d124b17c8cd32/certifi-2025.8.3-py3-none-any.whl",
         "sha256": "f6c12493cfb1b06ba2ff328595af9350c65d6644968e5d3a2ffd78699af217a5", "bytes": 161216,
         "python_runtime_dependencies": [], "package_license": "MPL-2.0", "identity_evidence": "actual-acquired-bytes-and-pypi-metadata"},
    ],
    "proj_database": {
        "source_wheel": "pyproj-3.7.2-cp312-cp312-win_amd64.whl", "filename": "proj.db", "wheel_member": "pyproj/proj_dir/share/proj/proj.db",
        "sha256": "47a7205d83ba6b7774b763f276ab57331f4dade2b2cfbcc0d486677e6543350b", "bytes": 9261056,
        "proj_version": "9.5.1", "epsg_version": "v11.022", "epsg_date": "2024-11-05", "proj_data_version": "1.20",
        "database_layout_major": "1", "database_layout_minor": "4", "identity_evidence": "actual-extracted-database-read-only-inspection",
    },
    "raw_wheel_inventory": {
        "sha256": "a6e84df188e7284e9fb7dba8cca521d04c294087209d10b5a5c3970eb0dac41f", "bytes": 9444,
        "scope": "raw-metadata-license-database-native-binary-inventory-no-import", "native_binary_counts": {"pyproj": 18, "pillow": 8, "certifi": 0},
    },
    "grid": {
        "filename": "us_noaa_g2018u0.tif", "url": "https://cdn.proj.org/us_noaa_g2018u0.tif",
        "sha256": "fa9a407ac7ee3f5a3694008e4bcd09ce9cc250452f0c3b11700a4960340abce2", "bytes": 16742155,
        "model": "GEOID18", "horizontal_frame": "NAD83(2011)", "horizontal_epoch": "2010.0", "vertical_datum": "NAVD88", "license": "Public Domain",
        "identity_evidence": "actual-acquired-bytes-and-official-registry",
        "readme": {"filename": "us_noaa_README.txt", "url": "https://cdn.proj.org/us_noaa_README.txt", "sha256": "38561c43f20756a77d33406c54cda8c250d18b6b30bff1e00ff51578e3682723", "bytes": 19653},
        "registry_snapshot": {"url": "https://cdn.proj.org/files.geojson", "sha256": "46f26c830faa164af9ef9ef51a7325a9d3800eb12ad4b1661c1d3143af7becc3", "bytes": 331044},
    },
    "layout": {"environment_relative_path": "environment", "sealed_proj_data_relative_path": "proj-data", "extra_proj_data_files": "reject", "user_cache": "isolated-empty-per-run", "working_directory": "isolated-empty-per-run"},
    "policy": {"PROJ_NETWORK": "OFF", "PROJ_ONLY_BEST_DEFAULT": "YES", "allow_ballpark": False, "only_best": True, "automatic_grid_download": False, "operation_selection": "separate-reviewed-explicit-contract-required", "missing_or_changed_input": "reject", "package_extras": [], "native_and_database_license_inventory": "required-before-use"},
}

RASTER = {
    "filename": "USGS_one_meter_x56y534_WA_Western_North_2016.tif", "bytes": 497020458,
    "sha256": "b62bd2d39d081642fd2b1710a2e3971a216702903b36812304a61ec79f6ac97e",
    "width": 10012, "height": 10012,
}
PROJ_PREFIX = "pyproj/proj_dir/share/proj/"
PROJ_DLL = "pyproj.libs/proj_9-c635a7dcf1c2f5308514f46a54311e70.dll"
MAX_WHEEL_FILES = 4096
MAX_WHEEL_MEMBER = 32 * 1024 * 1024
MAX_WHEEL_EXPANDED = 128 * 1024 * 1024
MAX_INSTALLED_BYTES = 768 * 1024 * 1024
MAX_QUALIFY_SECONDS = 1800
MAX_PEAK_WORKING_SET = 2 * 1024 * 1024 * 1024
