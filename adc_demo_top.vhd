library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity adc_demo_top is

    port (
        clk_25m  : in  STD_LOGIC;
        btn_down : in  STD_LOGIC;

        adc_csn  : out STD_LOGIC;
        adc_mosi : out STD_LOGIC;
        adc_miso : in  STD_LOGIC;
        adc_sclk : out STD_LOGIC;

        led      : out STD_LOGIC_VECTOR(7 downto 0)
    );

end adc_demo_top;


architecture Behavioral of adc_demo_top is

    signal adc_start :
        STD_LOGIC := '0';

    signal adc_busy :
        STD_LOGIC;

    signal adc_valid :
        STD_LOGIC;

    signal adc_data :
        STD_LOGIC_VECTOR(11 downto 0)
        := (others => '0');


    ------------------------------------------------------------
    -- Novo mjerenje svakih oko 10 ms
    --
    -- 25 MHz * 0.01 s = 250 000
    ------------------------------------------------------------

    signal sample_counter :
        integer range 0 to 249999 := 0;


    signal display_reg :
        STD_LOGIC_VECTOR(7 downto 0)
        := (others => '0');


begin


    ADC_MODULE :
        entity work.max11125_adc

        generic map (
            HALF_DIV => 12
        )

        port map (
            clk        => clk_25m,
            reset      => btn_down,

            start      => adc_start,

            ------------------------------------------------
            -- AIN0
            ------------------------------------------------
            channel    => "000",

            adc_csn    => adc_csn,
            adc_mosi   => adc_mosi,
            adc_miso   => adc_miso,
            adc_sclk   => adc_sclk,

            adc_value  => adc_data,

            data_valid => adc_valid,
            busy       => adc_busy
        );


    process(clk_25m)
    begin

        if rising_edge(clk_25m) then

            adc_start <= '0';


            if btn_down = '1' then

                sample_counter <= 0;

                display_reg <=
                    (others => '0');


            else

                ------------------------------------------------
                -- Periodicno pokreni ADC
                ------------------------------------------------

                if sample_counter = 249999 then

                    sample_counter <= 0;

                    if adc_busy = '0' then

                        adc_start <= '1';

                    end if;

                else

                    sample_counter <=
                        sample_counter + 1;

                end if;


                ------------------------------------------------
                -- Novi ADC rezultat
                ------------------------------------------------

                if adc_valid = '1' then

                  

                    display_reg <=
                        adc_data(11 downto 4);

                end if;

            end if;

        end if;

    end process;


    led <= display_reg;


end Behavioral;