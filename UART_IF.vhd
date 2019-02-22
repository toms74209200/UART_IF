-- =====================================================================
--  Title		: UART interface
--
--  File Name	: UART_IF.vhd
--  Project		: 
--  Block		:
--  Tree		:
--  Designer	: toms74209200
--  Created		: 2019/02/22
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity UART_IF is
	port(
		-- System --
		CLK			: in	std_logic;							--(p) Clock
		nRST		: in	std_logic;							--(n) Reset

		-- Control --
		ACC_WR		: in	std_logic;							--(p) Access start pulse
		ACC_RD		: out	std_logic;							--(p) Access received pulse
		ACC_BUSY	: out	std_logic;							--(p) Access busy flag
		ACC_END		: out	std_logic;							--(p) Access end pulse
		FIFO_EMPTY	: out	std_logic;							--(p) FIFO empty
		FIFO_FULL	: out	std_logic;							--(p) FIFO full
		ACC_WDAT	: in	std_logic_vector(7 downto 0);		--(p) Transmitted data
		ACC_RDAT	: out	std_logic_vector(7 downto 0);		--(p) Received data

		-- UART interface --
		RXD			: in	std_logic;							--(p) Received serial data
		TXD			: out	std_logic;							--(p) Transmitted serial data

		-- Simulation --
		TEST		: in	std_logic							--(p) Simulation mode
		);
end UART_IF;

architecture RTL of UART_IF is

constant ClkFrq			: integer := 48*10**6;					-- Clock frequency
constant BaudRate		: integer := 9600;						-- Baud rate
constant br_cycle		: integer := ClkFrq/BaudRate/2 - 1;		-- UART bus baud rate count(1/2)
constant str_cycle		: integer := ClkFrq/BaudRate/25 - 1;	-- START bit detect rate setting
constant Tc1ms			: integer := ClkFrq/10**3;				-- 1[msec] count


-- Internal signal --
signal str_cnt			: integer range 0 to ClkFrq/BaudRate/25 - 1;	--(p) START bit detect count
signal str_pls_i		: std_logic;									--(p) START bit detect pulse
signal str_det_ena		: std_logic;									--(p) Start access detect enable
signal str_det_cnt		: integer range 0 to 11;						--(p)
signal str_det			: std_logic;									--(p) Start access detect
signal br_rd_cnt		: integer range 0 to ClkFrq/BaudRate/2 - 1;		--(p) UART bus baud rate count(1/2)
signal br_rd_pls		: std_logic;									--(p) Baud rate timing pulse(1/2)
signal bit_rd_cnt		: std_logic;									--(p) Single bit count
signal bit_rd_pls		: std_logic;									--(p) Single bit timing pulse
signal byte_rd_cnt		: integer range 0 to 9;							--(p) Single byte count
signal byte_rd_end		: std_logic;									--(p) Single byte end
signal acc_end_i		: std_logic;									--(p) Access end pulse
signal rd_ena			: std_logic;									--(p) Read access enable
signal rd_end_i			: std_logic;									--(p) Read access end
signal acc_rdat_i		: std_logic_vector(ACC_RDAT'range);				--(p) Read data

signal br_wr_cnt		: integer range 0 to ClkFrq/BaudRate/2 - 1;		--(p) UART bus baud rate count(1/2)
signal br_wr_pls		: std_logic;									--(p) Baud rate timing pulse(1/2)
signal bit_wr_cnt		: std_logic;									--(p) Single bit count
signal bit_wr_pls		: std_logic;									--(p) Single bit timing pulse
signal byte_wr_cnt		: integer range 0 to 9;							--(p) Single byte count
signal byte_wr_end		: std_logic;									--(p) Single byte end
signal str_acc_ena		: std_logic;									--(p) Start access enable
signal wr_ena			: std_logic;									--(p) Write access enable
signal wr_lt			: std_logic;									--(p) ACC_WR pulse latch
signal acc_wdat_i		: std_logic_vector(7 downto 0);					--(p) Write data

signal empty			: std_logic;									--(p) Tx FIFO empty flag
signal full				: std_logic;									--(p) Tx FIFO full flag
signal mem_wdat_i		: std_logic_vector(7 downto 0);					--(p) Tx FIFO write data
signal mem_rdat_i		: std_logic_vector(7 downto 0);					--(p) Tx FIFO read data

-- components --
component TX_FIFO
port(
	clock		: IN STD_LOGIC ;
	data		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	rdreq		: IN STD_LOGIC ;
	wrreq		: IN STD_LOGIC ;
	empty		: OUT STD_LOGIC ;
	almost_full	: OUT STD_LOGIC ;
	q			: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
end component;

begin

-- ***********************************************************
--	Access busy flag
-- ***********************************************************
ACC_BUSY <= str_det_ena or rd_ena or str_acc_ena or wr_ena;


-- ***********************************************************
--	START bit detect rate counter
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		str_cnt <= 0;
	elsif (CLK'event and CLK = '1') then
		if (TEST = '0') then
			if (str_det_ena = '1') then
				if (str_pls_i = '1') then
					str_cnt <= 0;
				else
					str_cnt <= str_cnt + 1;
				end if;
			else
				str_cnt <= 0;
			end if;
		else
			str_cnt <= str_cycle;
		end if;
	end if;
end process;

str_pls_i <= '1' when (str_det_ena = '1' and str_cnt = str_cycle and str_det_cnt < 12) else
			 '1' when (str_det_ena = '1' and str_cnt = str_cycle/2 and str_det_cnt = 12) else '0';


-- ***********************************************************
--	Start access detect
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		str_det_ena <= '0';
	elsif (CLK'event and CLK = '1') then
		if (rd_ena = '0') then
			if (str_pls_i = '1') then
				if (str_det = '1') then
					str_det_ena <= '0';
				elsif (RXD = '1') then
					str_det_ena <= '0';
				end if;
			else
				if (RXD = '0') then
					str_det_ena <= '1';
				else
					str_det_ena <= '0';
				end if;
			end if;
		else
			str_det_ena <= '0';
		end if;
	end if;
end process;


-- ***********************************************************
--	START bit detect counter
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		str_det_cnt <= 0;
	elsif (CLK'event and CLK = '1') then
		if (str_det_ena = '1') then
			if (str_pls_i = '1') then
				if (str_det = '1') then
					str_det_cnt <= 0;
				else
					str_det_cnt <= str_det_cnt + 1;
				end if;
			end if;
		else
			str_det_cnt <= 0;
		end if;
	end if;
end process;

str_det <= '1' when (str_det_ena = '1' and str_det_cnt = 12 and str_pls_i = '1' and RXD = '0' and TEST = '0') else
		   '1' when (str_det_ena = '1' and str_det_cnt = 5 and str_pls_i = '1' and RXD = '0' and TEST = '1') else '0';


-- ***********************************************************
--	UART bus baud rate counter
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		br_rd_cnt <= 0;
	elsif (CLK'event and CLK = '1') then
		if (rd_ena = '1') then
			if (br_rd_pls = '1') then
				br_rd_cnt <= 0;
			else
				br_rd_cnt <= br_rd_cnt + 1;
			end if;
		else
			br_rd_cnt <= 0;
		end if;
	end if;
end process;

br_rd_pls <= '1' when (br_rd_cnt = br_cycle and TEST = '0') else
			 '1' when (br_rd_cnt = 5 and TEST = '1') else '0';


-- ***********************************************************
--	UART single bit pulse
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		bit_rd_cnt <= '0';
	elsif (CLK'event and CLK = '1') then
		if (rd_ena = '1') then
			if (br_rd_pls = '1') then
				bit_rd_cnt <= not bit_rd_cnt;
			end if;
		else
			bit_rd_cnt <= '0';
		end if;
	end if;
end process;

bit_rd_pls <= '1' when (bit_rd_cnt = '1' and br_rd_pls = '1') else '0';


-- ***********************************************************
--	Access bit counter
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		byte_rd_cnt <= 0;
	elsif (CLK'event and CLK = '1') then
		if (rd_ena = '1') then
			if (bit_rd_pls = '1') then
				if (byte_rd_end = '1') then
					byte_rd_cnt <= 0;
				else
					byte_rd_cnt <= byte_rd_cnt + 1;
				end if;
			end if;
		else
			byte_rd_cnt <= 0;
		end if;
	end if;
end process;

byte_rd_end <= '1' when (rd_ena = '1' and br_rd_pls = '1' and byte_rd_cnt = 9) else '0';


-- ***********************************************************
--	Access end pulse
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		acc_end_i <= '0';
	elsif (CLK'event and CLK = '1') then
		acc_end_i <= byte_rd_end or byte_wr_end;
	end if;
end process;

ACC_END <= acc_end_i;


-- ***********************************************************
--	Read access enable
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		rd_ena <= '0';
	elsif (CLK'event and CLK = '1') then
		if (byte_rd_end = '1') then
			rd_ena <= '0';
		elsif (str_det = '1') then
			rd_ena <= '1';
		end if;
	end if;
end process;


-- ***********************************************************
--	Read access end pulse
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		rd_end_i <= '0';
	elsif (CLK'event and CLK = '1') then
		if (byte_rd_end = '1') then
			rd_end_i <= '1';
		else
			rd_end_i <= '0';
		end if;
	end if;
end process;

ACC_RD <= rd_end_i;


-- ***********************************************************
--	Read data
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		acc_rdat_i <= (others => '0');
	elsif (CLK'event and CLK = '1') then
		if (rd_ena = '1' and bit_rd_pls = '1' and byte_rd_cnt < 8) then
			acc_rdat_i <= (RXD & acc_rdat_i(7 downto 1));
		end if;
	end if;
end process;

ACC_RDAT <= acc_rdat_i;


-- ***********************************************************
--	Start access enable
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		str_acc_ena <= '0';
	elsif (CLK'event and CLK = '1') then
		if (bit_wr_pls = '1') then
			str_acc_ena <= '0';
		elsif (wr_ena = '1') then
			str_acc_ena <= '0';
		elsif (empty = '0') then
			str_acc_ena <= '1';
		end if;
	end if;
end process;


-- ***********************************************************
--	Write access enable
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		wr_ena <= '0';
	elsif (CLK'event and CLK = '1') then
		if (byte_wr_end = '1') then
			wr_ena <= '0';
		elsif (str_acc_ena = '1' and bit_wr_pls = '1') then
			wr_ena <= '1';
		end if;
	end if;
end process;


-- ***********************************************************
--	UART bus baud rate counter
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		br_wr_cnt <= 0;
	elsif (CLK'event and CLK = '1') then
		if (str_acc_ena = '1' or wr_ena = '1') then
			if (br_wr_pls = '1') then
				br_wr_cnt <= 0;
			else
				br_wr_cnt <= br_wr_cnt + 1;
			end if;
		else
			br_wr_cnt <= 0;
		end if;
	end if;
end process;

br_wr_pls <= '1' when (br_wr_cnt = br_cycle and TEST = '0') else
			 '1' when (br_wr_cnt = 5 and TEST = '1') else '0';


-- ***********************************************************
--	UART single bit pulse
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		bit_wr_cnt <= '0';
	elsif (CLK'event and CLK = '1') then
		if (str_acc_ena = '1' or wr_ena = '1') then
			if (br_wr_pls = '1') then
				bit_wr_cnt <= not bit_wr_cnt;
			end if;
		else
			bit_wr_cnt <= '0';
		end if;
	end if;
end process;

bit_wr_pls <= '1' when (bit_wr_cnt = '1' and br_wr_pls = '1') else '0';


-- ***********************************************************
--	Access bit counter
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		byte_wr_cnt <= 0;
	elsif (CLK'event and CLK = '1') then
		if (str_acc_ena = '1' or wr_ena = '1') then
			if (bit_wr_pls = '1') then
				if (byte_wr_end = '1') then
					byte_wr_cnt <= 0;
				else
					byte_wr_cnt <= byte_wr_cnt + 1;
				end if;
			end if;
		else
			byte_wr_cnt <= 0;
		end if;
	end if;
end process;

byte_wr_end <= '1' when (bit_wr_pls = '1' and byte_wr_cnt = 9) else '0';


-- ***********************************************************
--	Write memory
-- ***********************************************************
mem_wdat_i <= ACC_WDAT;


U_TX_FIFO : TX_FIFO
port map(
	clock	=> CLK,
	data	=> mem_wdat_i,
	rdreq	=> byte_wr_end,
	wrreq	=> wr_lt,
	empty	=> empty,
	almost_full	=> full,
	q		=> mem_rdat_i
);

FIFO_EMPTY <= empty;
FIFO_FULL <= full;


-- ***********************************************************
--	ACC_WR pulse latch
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		wr_lt <= '0';
	elsif (CLK'event and CLK = '1') then
		wr_lt <= ACC_WR;
	end if;
end process;


-- ***********************************************************
--	Write data
-- ***********************************************************
process (CLK, nRST) begin
	if (nRST = '0') then
		acc_wdat_i <= (others => '0');
	elsif (CLK'event and CLK = '1') then
		if (wr_ena = '1') then
			if (bit_wr_pls = '1') then
				acc_wdat_i <= ('1' & acc_wdat_i(acc_wdat'left downto 1));
			end if;
		elsif (str_acc_ena = '1') then
			acc_wdat_i <= mem_rdat_i;
		end if;
	end if;
end process;

TXD <=	acc_wdat_i(0)	when (wr_ena = '1') else
		'0'				when (str_acc_ena = '1') else
		'1';


end RTL;	-- UART_IF
