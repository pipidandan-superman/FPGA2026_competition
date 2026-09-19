library verilog;
use verilog.vl_types.all;
entity yolo_ppu_xfer is
    generic(
        MAXSEG          : integer := 8
    );
    port(
        clk_i           : in     vl_logic;
        rst_i           : in     vl_logic;
        seg_we_i        : in     vl_logic;
        seg_len_i       : in     vl_logic_vector(31 downto 0);
        seg_m_i         : in     vl_logic_vector(31 downto 0);
        seg_s_i         : in     vl_logic_vector(5 downto 0);
        start_i         : in     vl_logic;
        nseg_i          : in     vl_logic_vector(3 downto 0);
        in_ready_o      : out    vl_logic;
        in_valid_i      : in     vl_logic;
        in_data_i       : in     vl_logic_vector(7 downto 0);
        y_valid_o       : out    vl_logic;
        y_o             : out    vl_logic_vector(7 downto 0);
        y_last_o        : out    vl_logic;
        busy_o          : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MAXSEG : constant is 2;
end yolo_ppu_xfer;
