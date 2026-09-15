/**********************************************************************************************
*																						      *
* Copyright (c) 2012 Analog Devices, Inc.  All Rights Reserved.                               *
* This software is proprietary and confidential to Analog Devices, Inc. and its licensors.    *
*                                                                                             *
***********************************************************************************************/
#include "wrapper.h"


CONSTANT UINT16 VicInfo[NUM_OF_VICS*4] = 
{/* H     V     I   Hz */
    0,    0,    0, 0,       /* 0 */
    640,  480,  0, 60,
    720,  480,  0, 60,
    720,  480,  0, 60,
    1280, 720,  0, 60,
    1920, 1080, 1, 60,      /* 5 */
    1440, 480,  1, 60,
    1440, 480,  1, 60,
    1440, 240,  0, 60,
    1440, 240,  0, 60,
    2880, 480,  1, 60,      /* 10 */
    2880, 480,  1, 60,
    2880, 240,  0, 60,
    2880, 240,  0, 60,
    1440, 480,  0, 60,
    1440, 480,  0, 60,      /* 15 */
    1920, 1080, 0, 60,
    720,  576,  0, 50,
    720,  576,  0, 50,
    1280, 720,  0, 50,
    1920, 1080, 1, 50,      /* 20 */
    1440, 576,  1, 50,
    1440, 576,  1, 50,
    1440, 288,  0, 50,
    1440, 288,  0, 50,
    2880, 576,  1, 50,      /* 25 */
    2880, 576,  1, 50,
    2880, 288,  0, 50,
    2880, 288,  0, 50,
    1440, 576,  0, 50,
    1440, 576,  0, 50,      /* 30 */
    1920, 1080, 0, 50,
    1920, 1080, 0, 24,
    1920, 1080, 0, 25,
    1920, 1080, 0, 30,
    2880, 480,  0, 60,      /* 35 */
    2880, 480,  0, 60,
    2880, 576,  0, 50,
    2880, 576,  0, 50,
    1920, 1080, 1, 50,
    1920, 1080, 1, 100,     /* 40 */
    1280, 720,  0, 100,
    720,  576,  0, 100,
    720,  576,  0, 100,
    1440, 576,  1, 100,
    1440, 576,  1, 100,     /* 45 */
    1920, 1080, 1, 120,
    1280, 720,  0, 120,
    720,  480,  0, 120,
    720,  480,  0, 120,
    1440, 480,  1, 120,     /* 50 */
    1440, 480,  1, 120,
    720,  576,  0, 200,
    720,  576,  0, 200, 
    1440, 576,  1, 200,
    1440, 576,  1, 200,     /* 55 */
    720,  480,  0, 200,
    720,  480,  0, 200, 
    1440, 480,  1, 200,
    1440, 480,  1, 200,
    1280, 720,  0, 24,      /* 60 */
    1280, 720,  0, 25,
    1280, 720,  0, 30,
    1920, 1080, 0, 120,
    1920, 1080, 0, 100
                            /* 65 */      
};

#if TX_USER_INIT
CONSTANT UCHAR UserTxRegInitTable[] = {0};
CONSTANT UCHAR UserTxFieldInitTable[] = {0};
#endif


void DBG_Printf(const char *data, ...)
{
}

void adi_memcpy(void *dst,void* src, UINT32 count)
{
	return;
}

void adi_memset(void *dst,UINT8 data, UINT32 count)
{
	return;
}
/*===========================================================================
 * Get the elapsed time in milliseconds from a defined starting point
 *
 * Entry:   StartCount  = Time in milliseconds at the sarting point
 *          CurrMsCount = Pointer to receive the current time in milliseconds
 *                        Can be set to NULL if not needed
 *
 * Return:  Time (in milliseconds) that elapsed since StartCount.
 *          This function can not return elapsed time over 65 seconds
 *
 *==========================================================================*/
UINT32 ATV_GetElapsedMs (UINT32 StartCount, UINT32 *CurrMsCount)
{
    UINT32 Elapsed = 0;
    return (Elapsed);
}

/*===========================================================================
 * Return the current time in milliseconds. 
 * If the current time is 0, return 0xFFFFFFFF
 *
 *
 *==========================================================================*/
UINT32 ATV_GetMsCountNZ (void)
{
    UINT32 i = 0;
    return(i);
}

/*============================================================================
 * Read up to 8-bit field from a single 8-bit register
 *              ________   
 * Example     |___***__|  Mask = 0x1C     BitPos = 2
 *
 *
 * Entry:   DevAddr = Device Address
 *          RegAddr = 8-bit register address
 *          Mask    = Field mask
 *          BitPos  = Field LSBit position in the register (0-7)
 *
 * Return:  Field value in the LSBits of the return value
 *
 *===========================================================================*/
UCHAR ATV_I2CReadField8 (UCHAR DevAddr, UCHAR RegAddr, UCHAR Mask, 
                         UCHAR BitPos)
{
	return 1;
}

/*============================================================================
 * Write up to 8-bit field to a single 8-bit register
 *              ________   
 * Example     |___****_|  Mask = 0x1E     BitPos = 1
 *
 * Entry:   DevAddr = Device Address
 *          RegAddr = 8-bit register address
 *          Mask    = Field mask
 *          BitPos  = Field LSBit position in the register (0-7)
 *                    Set to 0 if FieldVal is in correct position of the reg
 *          FieldVal= Value (in the LSBits) of the field to be written
 *                    If FieldVal is already in the correct position (i.e., 
 *                    does not need to be shifted,) set BitPos to 0
 *
 * Return:  None
 *
 *===========================================================================*/
void ATV_I2CWriteField8 (UCHAR DevAddr, UCHAR RegAddr, UCHAR Mask, 
                         UCHAR BitPos, UCHAR FieldVal)
{
}

/*============================================================================
 * Read up to 32-bit field from two or more consecutive 8-bit registers in
 * Big Endian format
 *
 *                   ________
 * Start Reg Addr-> |     ***|  MSbits          MsbMask = 0x07
 *                  |********|  Middle bits
 *                  |********|  Middle bits
 *                  |********|  Middle bits
 * End Reg Addr---> |**______|  LSbits          LsbMask = 0xC0, LsbPos = 6
 *                                              FldSpan = 5
 *
 * Entry:   DevAddr = Device Address
 *          RegAddr = Starting 8-bit register address
 *          MsbMask = Mask for MSbits
 *          LsbMask = Mask for LSbits
 *          LsbPos  = LSbit position (0-7)
 *          FldSpan = Number of consecutive registers containing field bits
 *                    (Maximum 5 registers)
 *
 * Return:  Field value in the LSBits of the return value
 *
 *===========================================================================*/
UINT32 ATV_I2CReadField32 (UCHAR DevAddr, UCHAR RegAddr, UCHAR MsbMask, 
                           UCHAR LsbMask, UCHAR LsbPos, UCHAR FldSpan)
{
    return 1;
}

/*============================================================================
 * Read up to 32-bit field from two or more consecutive 8-bit registers in
 * Little Endian format
 *
 *                   ________  
 * Start Reg Addr-> |***     |  LSbits          LsbMask = 0xE0, LsbPos = 5
 *                  |********|  Middle bits
 *                  |********|  Middle bits
 *                  |********|  Middle bits
 * End Reg Addr---> |______**|  MSbits          MsbMask = 0x03
 *                                              FldSpan = 5
 *
 * Entry:   DevAddr = Device Address
 *          RegAddr = Starting 8-bit register address
 *          MsbMask = Mask for MSbits
 *          LsbMask = Mask for LSbits
 *          LsbPos  = LSbit position (0-7)
 *          FldSpan = Number of consecutive registers containing field bits
 *                    (Maximum 5 registers)
 *
 * Return:  Field value in the LSBits of the return value
 *
 *===========================================================================*/
UINT32 ATV_I2CReadField32LE (UCHAR DevAddr, UCHAR RegAddr, UCHAR MsbMask, 
                             UCHAR LsbMask, UCHAR LsbPos, UCHAR FldSpan)
{
    return 1;
}

/*============================================================================
 * Write up to 32-bit field to two or more consecutive 8-bit registers in
 * Big Endian format
 *                   ________
 * Start Reg Addr-> |   *****|  MSbits          MsbMask = 0x1F
 *                  |********|  Middle bits
 * End Reg Addr---> |******__|  LSbits          LsbMask = 0xFC, LsbPos = 2
 *                                              FldSpan = 3
 * Entry:   DevAddr = Device Address
 *          RegAddr = Starting 8-bit register address
 *          MsbMask = Mask for MSbits
 *          LsbMask = Mask for LSbits
 *          LsbPos  = LSbit position (0-7)
 *          FldSpan = Number of consecutive registers containing field bits
 *          Val     = Field value (in the LSBits) to be written
 *
 * Return:  None
 *
 *
 *===========================================================================*/
void ATV_I2CWriteField32 (UCHAR DevAddr, UCHAR RegAddr, UCHAR MsbMask, 
                     UCHAR LsbMask, UCHAR LsbPos, UCHAR FldSpan, UINT32 Val)
{
}

/*===========================================================================
 * Modify multiple registers fields from a user-supllied table
 *
 * Entry:   Table : A pointer to the table of writes that must be performed
 *                  Table[] = { 
 *                              DevAddr0, RegOffset0, Mask0, Value0,
 *                              DevAddr1, RegOffset1, Mask1, Value1,
 *                              DevAddr2, RegOffset2, Mask2, Value2,
 *                              ...
 *                              DevAddrN, RegOffsetN, MaskN, ValueN,
 *                              EndVal
 *                             }
 *          EndVal : The last value in the table
 *
 * Return:  None
 *
 *==========================================================================*/
void ATV_I2CWriteFields (UCHAR *Table, UCHAR EndVal)
{
}

/*============================================================================
 * Write up to 32-bit field to two or more consecutive 8-bit registers in
 * Little Endian format
 *                   ________
 * Start Reg Addr-> |*       |  LSbits          LsbMask = 0x80, LsbPos = 7
 *                  |********|  Middle bits
 *                  |********|  Middle bits
 * End Reg Addr---> |********|  MSbits          MsbMask = 0xFF
 *                                              FldSpan = 4
 * Entry:   DevAddr = Device Address
 *          RegAddr = Starting 8-bit register address
 *          MsbMask = Mask for MSbits
 *          LsbMask = Mask for LSbits
 *          LsbPos  = LSbit position (0-7)
 *          FldSpan = Number of consecutive registers containing field bits
 *          Val     = Field value (in the LSBits) to be written
 *
 * Return:  None
 *
 *
 *===========================================================================*/
void ATV_I2CWriteField32LE (UCHAR DevAddr, UCHAR RegAddr, UCHAR MsbMask, 
                     UCHAR LsbMask, UCHAR LsbPos, UCHAR FldSpan, UINT32 Val)
{
}

/*===========================================================================
 * Perform multiple I2C register writes from a user-supplied Table
 *
 * Entry:   Table : A pointer to the table of writes that must be performed
 *                  Table[] = { 
 *                              DevAddr0, RegOffset0, Value0,
 *                              DevAddr1, RegOffset1, Value1,
 *                              DevAddr2, RegOffset2, Value2,
 *                              ...
 *                              DevAddrN, RegOffsetN, ValueN,
 *                              EndVal
 *                             }
 *          EndVal : The last value in the table
 *
 * Return:  None
 *
 *==========================================================================*/
void ATV_I2CWriteTable (UCHAR *Table, UCHAR EndVal)
{
}

/*===========================================================================
 * Look for UCHAR Value in Table with Step increments
 *
 * Return:  Offset of matching value or end value
 *
 *==========================================================================*/
UINT16 ATV_LookupValue8 (UCHAR *Table, UCHAR Value, UCHAR EndVal, UINT16 Step)
{
    UINT16 i=0;
    return(i);
}

/*===========================================================================
 * Print current system time
 *
 * Entry:   Gran    = 0  for ms
 *                    1  for sec:ms
 *                    2  for min:sec:ms
 *          PostFix = Postfix string
 *
 *==========================================================================*/
void ATV_PrintTime (char *Prefix, UCHAR Gran, char *Postfix)
{
}

/*===========================================================================
 *
 *==========================================================================*/
void HAL_DelayMs (UINT16 Counter)
{
	WaitMilliSec(Counter);
}

/*===========================================================================
 *
 *==========================================================================*/
UINT16 HAL_I2CReadBlock (UCHAR Dev, UCHAR Reg, UCHAR *Data, UINT16 NofBytes)
{
	return 1;
}

/*===========================================================================
 *
 *==========================================================================*/
UINT16  HAL_I2CWriteBlock (UCHAR Dev, UCHAR Reg, UCHAR *Data, UINT16 NumberBytes)
{
	return 1;
}

/*===========================================================================
 *
 *==========================================================================*/
UCHAR HAL_I2CReadByte (UCHAR Dev, UCHAR Reg, UCHAR *Data)
{
    return 1;
}

/*===========================================================================
 *
 *==========================================================================*/
UCHAR HAL_I2CWriteByte (UCHAR Dev, UCHAR Reg, UCHAR Data)
{
    return 1;
}

UCHAR HAL_SetRxChipSelect(UCHAR DevIdx)
{
    return 1;
}

/**
 * Wait for passed number of milli-seconds
 */
void WaitMilliSec(unsigned int msec)
{
}

/*============================================================================
 * Reset CEC controller
 * 
 * Entry:   None
 * 
 * Return:  ATVERR_OK
 * 
 *===========================================================================*/
ATV_ERR CEC_Reset (void)
{
	return ATVERR_OK;
}

/*============================================================================
 * Enable/Disable CEC controller
 * 
 * Entry:   Enable = TRUE to enable CEC controller
 *                   FALSE to disable
 * 
 * Return:  ATVERR_OK
 * 
 *===========================================================================*/
ATV_ERR CEC_Enable (BOOL Enable)
{
	return ATVERR_OK;
}

/*============================================================================
 * Set the logical address for one of 3 logical devices
 * 
 * Entry:   LogAddr = Logical address for the device
 *          DevId   = The device to set the logical address to. (0, 1 or 2)
 *          Enable  = TRUE to enable the logical device
 *                    FALSE to disable the logical device
 * 
 * Return:  ATVERR_OK
 *          ATVERR_INV_PARM if DevId is larger than 2
 * 
 *===========================================================================*/
ATV_ERR CEC_SetLogicalAddr (UCHAR LogAddr, UCHAR DevId, BOOL Enable)
{
    return ATVERR_OK;
}

/*============================================================================
 * Send message to CEC
 * 
 * Entry:   MsgPtr = Pointer to the message to be sent
 *          MsgLen
 * 
 * Return:  ATVERR_OK
 *          ATVERR_FAILED if CEC controller is busy
 *          ATVERR_INV_PARM if MsgLen is larger than max message size
 * 
 *===========================================================================*/
ATV_ERR CEC_SendMessage (UCHAR *MsgPtr, UCHAR MsgLen)
{
  	return ATVERR_OK;
}

/*============================================================================
 * Send out CEC message in buffer 
 * 
 * Entry:   
 * 
 * Return:  ATVERR_OK
 *          ATVERR_FAILED if CEC controller is busy
 * 
 * Note:    HDMI spec 1.4
 *          Section CEC 9.2    Message Time Constraints
 *          There are certain time constraints for messages that should be 
 *          obeyed at application level. These are a desired maximum response 
 *          time of 200ms and a required maximum response time of 1 second.
 *===========================================================================*/
ATV_ERR CEC_SendMessageOut (void)
{
  	return ATVERR_OK;
}

/*============================================================================
 * Resend last sent message to CEC
 * 
 * Entry:   None
 * 
 * Return:  ATVERR_OK
 *          ATVERR_FAILED if CEC controller is busy
 * 
 *===========================================================================*/
ATV_ERR CEC_ResendLastMessage (void)
{
    return ATVERR_OK;
}


/*============================================================================
 *
 * Entry:   CecInts = CEC interrupts
 * 
 * Return:  None
 * 
 * 
 *===========================================================================*/
void CEC_Isr (CEC_INTERRUPTS *CecInts)
{

}

/*============================================================================
 * Perform logical address allocation
 *
 * Entry:   LogAddrList = Pointer to a prioritized list of logical addresses 
 *                        that the device will try to obtain, terminated by
 *                        0xff.
 *
 * Return:  ATVERR_OK
 *          ATVERR_FAILED if CEC is busy
 *          ATVERR_INV_PARM if LogAddrList is too long or contains no data
 * 
 * This function returns immediately. If a logical address slot is found,
 * the caller will be notified by the event ADI_EVENT_CEC_LOG_ADDR_ALLOC
 * 
 *===========================================================================*/
ATV_ERR CEC_AllocateLogAddr (UCHAR *LogAddrList)
{
   return ATVERR_OK;
}
