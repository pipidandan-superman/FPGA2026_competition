library verilog;
use verilog.vl_types.all;
entity yolo_ppu_maxpool5 is
    generic(
        MAXW            : integer := 64
    );
    port(
        clk_i           : in     vl_logic;
        rst_i           : in     vl_logic;
        start_i         : in     vl_logic;
        c_i             : in     vl_logic_vector(15 downto 0);
        h_i             : in     vl_logic_vector(15 downto 0);
        w_i             : in     vl_logic_vector(15 downto 0);
        in_ready_o      : out    vl_logic;
        in_valid_i      : in     vl_logic;
        in_data_i       : in     vl_logic_vector(7 downto 0);
        out_valid_o     : out    vl_logic;
        out_data_o      : out    vl_logic_vector(7 downto 0);
        out_last_o      : out    vl_logic;
        busy_o          : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MAXW : constant is 2;
end yolo_ppu_maxpool5;
