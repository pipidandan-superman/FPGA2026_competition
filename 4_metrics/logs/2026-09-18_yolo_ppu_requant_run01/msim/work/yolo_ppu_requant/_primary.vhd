library verilog;
use verilog.vl_types.all;
entity yolo_ppu_requant is
    generic(
        R               : integer := 1
    );
    port(
        clk_i           : in     vl_logic;
        rst_i           : in     vl_logic;
        in_valid_i      : in     vl_logic;
        in_last_i       : in     vl_logic;
        x_i             : in     vl_logic_vector;
        m_i             : in     vl_logic_vector;
        sh_i            : in     vl_logic_vector;
        y_valid_o       : out    vl_logic;
        y_last_o        : out    vl_logic;
        y_o             : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of R : constant is 2;
end yolo_ppu_requant;
