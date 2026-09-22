library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity max11125_adc is

    generic (
        -- Sistemski takt ULX3S = 25 MHz
        --
        -- SPI SCLK se dobija:
        -- f_sclk = 25 MHz / (2 * HALF_DIV)
        --
        -- Za HALF_DIV = 12:
        -- f_sclk ˜ 1.04 MHz
        HALF_DIV : positive := 12
    );

    port (
        clk       : in  STD_LOGIC;
        reset     : in  STD_LOGIC;

        -- Jednotaktni impuls za pokretanje novog mjerenja
        start     : in  STD_LOGIC;

        -- Izbor jednog od 8 analognih kanala:
       
        channel   : in  STD_LOGIC_VECTOR(2 downto 0);

        -- SPI interfejs prema MAX11125
        adc_csn   : out STD_LOGIC;
        adc_mosi  : out STD_LOGIC;
        adc_miso  : in  STD_LOGIC;
        adc_sclk  : out STD_LOGIC;

        
        adc_value : out STD_LOGIC_VECTOR(11 downto 0);

       
        data_valid : out STD_LOGIC;

       
        busy       : out STD_LOGIC
    );

end max11125_adc;


architecture Behavioral of max11125_adc is

    ------------------------------------------------------------
    -- MAX11125 koristi SPI nacin:
    --
    -- CPOL = 1
    -- CPHA = 1
    --
    -- SCLK zato u stanju mirovanja ima vrijednost '1'.
    ------------------------------------------------------------

    type state_type is (
        IDLE,
        CLK_FALL,
        CLK_RISE,
        FRAME_END,
        FRAME_GAP
    );

    signal state :
        state_type := IDLE;


    ------------------------------------------------------------
    -- SPI izlazni registri
    ------------------------------------------------------------

    signal cs_reg :
        STD_LOGIC := '1';

    signal sclk_reg :
        STD_LOGIC := '1';

    signal mosi_reg :
        STD_LOGIC := '0';


    ------------------------------------------------------------
    -- Naredba koja se šalje MAX11125
    --
    -- Struktura ADC Mode Control registra:
    --
    -- bit 15      = 0       -> ADC Mode Control
    -- bits 14:11  = 0001    -> Manual mode
    -- bits 10:7   = CHSEL   -> izbor kanala
    -- bits 6:5    = 00      -> bez reseta
    -- bits 4:3    = 00      -> normal power mode
    -- bit 2       = 0       -> CHAN_ID iskljucen
    -- bit 1       = 0       -> SWCNV
    -- bit 0       = 0       -> unused
    ------------------------------------------------------------

    signal command_word :
        STD_LOGIC_VECTOR(15 downto 0)
        := x"0800";


    ------------------------------------------------------------
    -- Registar u koji se serijski prima DOUT/MISO
    ------------------------------------------------------------

    signal rx_shift :
        STD_LOGIC_VECTOR(15 downto 0)
        := (others => '0');


    ------------------------------------------------------------
    -- Trenutni bit SPI okvira
    ------------------------------------------------------------

    signal bit_index :
        INTEGER range 0 to 15 := 15;


    ------------------------------------------------------------
    -- Manual mode ima kašnjenje od jednog okvira:
    --
    -- frame 0 -> zadaj kanal
    -- frame 1 -> primi rezultat prethodne konverzije
    ------------------------------------------------------------

    signal frame_number :
        INTEGER range 0 to 1 := 0;


    ------------------------------------------------------------
    -- Dijelitelj sistemskog takta
    ------------------------------------------------------------

    signal div_counter :
        INTEGER range 0 to HALF_DIV - 1 := 0;


    ------------------------------------------------------------
    -- Kratka pauza izmedu dva SPI okvira
    ------------------------------------------------------------

    signal gap_counter :
        INTEGER range 0 to (2 * HALF_DIV) - 1 := 0;


    signal busy_reg :
        STD_LOGIC := '0';

    signal valid_reg :
        STD_LOGIC := '0';

    signal value_reg :
        STD_LOGIC_VECTOR(11 downto 0)
        := (others => '0');


begin

    ------------------------------------------------------------
    -- Izlazi modula
    ------------------------------------------------------------

    adc_csn  <= cs_reg;
    adc_sclk <= sclk_reg;
    adc_mosi <= mosi_reg;

    adc_value  <= value_reg;
    data_valid <= valid_reg;
    busy       <= busy_reg;


   
    process(clk)
    begin

        if rising_edge(clk) then

            ----------------------------------------------------
            -- data_valid traje samo jedan sistemski takt
            ----------------------------------------------------

            valid_reg <= '0';


            if reset = '1' then

                state <= IDLE;

                cs_reg   <= '1';
                sclk_reg <= '1';
                mosi_reg <= '0';

                command_word <= x"0800";

                rx_shift <= (others => '0');

                bit_index    <= 15;
                frame_number <= 0;

                div_counter <= 0;
                gap_counter <= 0;

                busy_reg  <= '0';
                valid_reg <= '0';

                value_reg <= (others => '0');


            else

                case state is


                    ------------------------------------------------
                    -- CEKANJE ZAHTJEVA ZA NOVO MJERENJE
                    ------------------------------------------------

                    when IDLE =>

                        cs_reg   <= '1';
                        sclk_reg <= '1';

                        busy_reg <= '0';

                        div_counter <= 0;
                        gap_counter <= 0;


                        if start = '1' then

                            busy_reg <= '1';

                            ------------------------------------------------
                            -- Formiranje ADC Mode Control naredbe
                            --
                            -- Manual mode = 0001
                            --
                          
                            ------------------------------------------------

                            command_word <=
                                '0' &
                                "0001" &
                                ('0' & channel) &
                                "0000000";


                            frame_number <= 0;

                            bit_index <= 15;

                            rx_shift <=
                                (others => '0');


                            ------------------------------------------------
                            -- Prvi DIN bit je bit 15 i jednak je 0.
                            ------------------------------------------------

                            mosi_reg <= '0';


                            ------------------------------------------------
                            -- CS = 0 oznacava pocetak SPI okvira
                            ------------------------------------------------

                            cs_reg <= '0';

                            state <= CLK_FALL;

                        end if;



                    ------------------------------------------------
                    -- OPADAJUCA IVICA SCLK
                    --
                    -- MAX11125 na opadajucoj ivici ažurira DOUT.
                    ------------------------------------------------

                    when CLK_FALL =>

                        if div_counter = HALF_DIV - 1 then

                            div_counter <= 0;

                            sclk_reg <= '0';

                            state <= CLK_RISE;

                        else

                            div_counter <=
                                div_counter + 1;

                        end if;



                    ------------------------------------------------
                    -- RASTUCA IVICA SCLK
                    --
                    -- MAX11125 prihvata DIN/MOSI podatak na
                    -- rastucoj ivici.
                    --
                    -- MISO je tada stabilan i FPGA ga ocitava.
                    ------------------------------------------------

                    when CLK_RISE =>

                        if div_counter = HALF_DIV - 1 then

                            div_counter <= 0;

                            sclk_reg <= '1';

                            ------------------------------------------------
                            -- Ocitavanje trenutnog DOUT bita
                            ------------------------------------------------

                            rx_shift(bit_index) <= adc_miso;


                            if bit_index = 0 then

                                ------------------------------------------------
                                -- Preneseno je svih 16 bitova
                                ------------------------------------------------

                                state <= FRAME_END;

                            else

                                ------------------------------------------------
                                -- Priprema narednog DIN/MOSI bita
                                ------------------------------------------------

                                bit_index <=
                                    bit_index - 1;

                                mosi_reg <=
                                    command_word(
                                        bit_index - 1
                                    );

                                state <= CLK_FALL;

                            end if;


                        else

                            div_counter <=
                                div_counter + 1;

                        end if;



                    ------------------------------------------------
                    -- ZAVRŠETAK SPI OKVIRA
                    ------------------------------------------------

                    when FRAME_END =>

                        if div_counter = HALF_DIV - 1 then

                            div_counter <= 0;

                            cs_reg   <= '1';
                            sclk_reg <= '1';


                            if frame_number = 0 then

                                ------------------------------------------------
                                -- Prvi okvir je zadao kanal i izvršio
                                -- konverziju.
                                --
                                -- U Manual modu rezultat se pojavljuje
                                -- u narednom SPI okviru.
                                ------------------------------------------------

                                gap_counter <= 0;

                                state <= FRAME_GAP;


                            else

                                ------------------------------------------------
                                -- CHAN_ID = 0
                                --
                                -- MAX11125 DOUT okvir:
                                --
                                -- bit 15      = 0
                                -- bits 14:3   = ADC[11:0]
                                -- bits 2:0    = 000
                                ------------------------------------------------

                                value_reg <=
                                    rx_shift(14 downto 3);

                                valid_reg <= '1';

                                busy_reg <= '0';

                                state <= IDLE;

                            end if;

                        else

                            div_counter <=
                                div_counter + 1;

                        end if;



                    ------------------------------------------------
                    -- PAUZA IZMEÐU PRVOG I DRUGOG OKVIRA
                    ------------------------------------------------

                    when FRAME_GAP =>

                        cs_reg   <= '1';
                        sclk_reg <= '1';


                        if gap_counter =
                           (2 * HALF_DIV) - 1 then

                            gap_counter <= 0;

                            frame_number <= 1;

                            bit_index <= 15;

                            rx_shift <=
                                (others => '0');

                            ------------------------------------------------
                            -- Prvi bit nove naredbe
                            ------------------------------------------------

                            mosi_reg <= '0';

                            ------------------------------------------------
                            -- Pocetak drugog SPI okvira
                            ------------------------------------------------

                            cs_reg <= '0';

                            state <= CLK_FALL;

                        else

                            gap_counter <=
                                gap_counter + 1;

                        end if;



                    when others =>

                        state <= IDLE;

                end case;

            end if;

        end if;

    end process;


end Behavioral;