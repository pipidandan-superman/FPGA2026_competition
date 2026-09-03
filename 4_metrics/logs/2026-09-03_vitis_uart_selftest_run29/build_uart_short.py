import shutil
import vitis
workspace = 'C:/vws_uart_s5'
hardware_xsa = 'E:/competition/2_fpga/0_diaplay_test/vitis/display_test_wrapper.xsa'
source_dir = 'E:/competition/2_fpga/0_diaplay_test/vitis/app_component/src'
shutil.rmtree(workspace, ignore_errors=True)
client = vitis.create_client(workspace=workspace)
platform = client.create_platform_component(name='display_test_platform', hw_design=hardware_xsa)
platform_status = platform.build()
print('platform build status:', platform_status)
client.add_platform_repos('C:/vws_uart_s5/display_test_platform/export')
client.rescan_platform_repos('C:/vws_uart_s5/display_test_platform/export')
platform_xpfm = client.find_platform_in_repos('display_test_platform')
print('platform xpfm:', platform_xpfm)
component = client.create_app_component(name='uart_selftest_build', platform=platform_xpfm, domain='standalone_ps7_cortexa9_0', template='empty_application')
component.import_files(from_loc=source_dir, files=['main.c'], dest_dir_in_cmp='src')
status = component.build()
print('build status:', status)
vitis.dispose()
if platform_status != 0: raise SystemExit(platform_status)
if status != 0: raise SystemExit(status)
