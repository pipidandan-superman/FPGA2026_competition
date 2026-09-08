/************************************************************************
 * File Name       : platform_config.h
 * Developer       : LSL
 * Date            : 2026-09-08
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : platform_config
 * Description     : Supplies PLATFORM_EMAC_BASEADDR used by the AMD
 *                   lwip_echo_server template platform files; maps to the
 *                   Zynq PS GEM0 (ps7_ethernet_0) base address.
 * Dependencies    : xparameters.h must be included before this header.
 * Revision History:
 *   - V1.0 (2026-09-08) by LSL : Initial release.
 ************************************************************************/

#ifndef __PLATFORM_CONFIG_H_
#define __PLATFORM_CONFIG_H_

#define PLATFORM_EMAC_BASEADDR XPAR_XEMACPS_0_BASEADDR

#endif
