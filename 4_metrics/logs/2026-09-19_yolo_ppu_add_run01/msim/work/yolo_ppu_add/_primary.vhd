library verilog;
use verilog.vl_types.all;
entity yolo_ppu_add is
    port(
        clk_i           : in     vl_logic;
        rst_i           : in     vl_logic;
        start_i         : in     vl_logic;
        n_i             : in     vl_logic_vector(31 downto 0);
        ma_i            : in     vl_logic_vector(31 downto 0);
        sa_i            : in     vl_logic_vector(5 downto 0);
        mb_i            : in     vl_logic_vector(31 downto 0);
        sb_i            : in     vl_logic_vector(5 downto 0);
        a_ready_o       : out    vl_logic;
        a_valid_i       : in     vl_logic;
        a_data_i        : in     vl_logic_vector(7 downto 0);
        b_ready_o       : out    vl_logic;
        b_valid_i       : in     vl_logic;
        b_data_i        : in     vl_logic_vector(7 downto 0);
        y_valid_o       : out    vl_logic;
        y_o             : out    vl_logic_vector(7 downto 0);
        y_last_o        : out    vl_logic;
        busy_o          : out    vl_logic
    );
end yolo_ppu_add;
