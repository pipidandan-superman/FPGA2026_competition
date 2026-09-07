# ADV7511 package project-reference check

Date: 2026-09-06 13:12  
Result: PASS

## Change

`E:\competition\2_fpga\1_zynqtest_2025\project_1\project_1.xpr` was changed from
the imported project-local copy:

```text
$PSRCDIR/sources_1/imports/hdmi_new/adv7511_init_table_pkg.sv
```

to the explicit external source:

```text
$PPRDIR/../../0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv
```

The stale `ImportPath` and `ImportTime` attributes were removed.

## Validation

The XPR loads as XML. The package entry resolves to:

```text
E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table_pkg.sv
```

That resolved path exists and has zero import attributes. The project no longer
contains any file entry under `$PSRCDIR/sources_1/imports/`.

At the time of the change, the now-unreferenced imported copy under
`project_1.srcs` still had the same SHA-256 as the active source:

```text
02C6DC9620215C2914251DDD6C3D2B8E7C1C79F7EC850A77E32B36E77538D48A
```

The stale copy was intentionally retained. Future edits must use the active
external path above.
