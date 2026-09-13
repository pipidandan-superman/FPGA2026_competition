import io
import unittest
from hardware_contract import validate_reset_contract


def fixture(aux='one', value='1', polarity='0', debug='zero', locked='one'):
    return io.StringIO(f'''<SYSTEM><MODULES>
    <MODULE INSTANCE="const_one"><PARAMETERS><PARAMETER NAME="CONST_VAL" VALUE="{value}"/></PARAMETERS><PORTS><PORT NAME="dout" SIGNAME="one"/></PORTS></MODULE>
    <MODULE INSTANCE="const_zero"><PARAMETERS><PARAMETER NAME="CONST_VAL" VALUE="0"/></PARAMETERS><PORTS><PORT NAME="dout" SIGNAME="zero"/></PORTS></MODULE>
    <MODULE INSTANCE="control_reset"><PARAMETERS><PARAMETER NAME="C_EXT_RESET_HIGH" VALUE="0"/><PARAMETER NAME="C_AUX_RESET_HIGH" VALUE="{polarity}"/></PARAMETERS><PORTS><PORT NAME="aux_reset_in" SIGNAME="{aux}"/><PORT NAME="dcm_locked" SIGNAME="{locked}"/><PORT NAME="mb_debug_sys_rst" SIGNAME="{debug}"/></PORTS></MODULE>
    </MODULES></SYSTEM>''')


class ResetContractTests(unittest.TestCase):
    def test_correct(self):
        self.assertEqual(validate_reset_contract(fixture())['aux_constant'], 1)

    def test_vivado_hex_constant(self):
        self.assertEqual(validate_reset_contract(fixture(value='0x1'))['aux_constant'], 1)

    def test_original_fault(self):
        with self.assertRaisesRegex(ValueError, 'aux_reset_in'):
            validate_reset_contract(fixture(aux='zero'))

    def test_polarity(self):
        with self.assertRaises(ValueError):
            validate_reset_contract(fixture(polarity='1'))

    def test_constant_value(self):
        with self.assertRaises(ValueError):
            validate_reset_contract(fixture(value='0'))

    def test_debug_reset(self):
        with self.assertRaises(ValueError):
            validate_reset_contract(fixture(debug='one'))

    def test_unlocked_clock(self):
        with self.assertRaises(ValueError):
            validate_reset_contract(fixture(locked='zero'))


if __name__ == '__main__':
    unittest.main()
