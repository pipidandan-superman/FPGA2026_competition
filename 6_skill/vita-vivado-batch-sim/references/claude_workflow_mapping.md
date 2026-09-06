# Claude workflow mapping

The Claude-derived workflow in `D:\VitA\6_proj\vitis_test` supplies the valid
batch structure: absolute Vivado path, `-mode batch`, TCL-controlled filesets
and IP generation, and external monitoring. This skill adds run isolation,
exact PID handling, machine result files, stable markers, hashes, timeout
cleanup, and real-DMA coverage checks.

The existing `tb_axi_dma_ip.v` explicitly uses a simplified placeholder. It is
only a control-flow smoke test until replaced by an official AXI DMA instance.
