module fingerprint_uart_demo(
    input wire clk,          // 100 MHz clock
    input wire rst,          // active high reset
    input wire uart_rx_pin,  // RX from R307S TXD
    output wire uart_tx_pin, // TX to R307S RXD
    output wire led          // Status LED (LD0)
);
    // UART parameters
    parameter CLK_FREQ = 100_000_000; // 100 MHz
    parameter BAUD = 57600;
    localparam TICKS = CLK_FREQ / BAUD;

    // UART TX signals
    reg tx_start = 0;
    reg [7:0] tx_data = 8'h00;
    wire tx_busy;
    wire tx_pin;

    // UART RX signals
    wire [7:0] rx_data;
    wire rx_ready;
    wire rx_pin = uart_rx_pin;

    // LED logic
    reg led_reg = 0;
    assign led = led_reg;
    assign uart_tx_pin = tx_pin;

    // Handshake packet storage
    reg [7:0] handshake_pkt[0:11];
    reg [3:0] pkt_idx = 0;

    // State machine
    reg [27:0] counter = 0;
    reg [2:0] state = 0;

    // UART TX module
    reg [3:0] tx_bitnum = 0;
    reg [15:0] tx_cnt = 0;
    reg [9:0] tx_shifter = 10'b1111111111;
    reg tx_active = 0;
    reg tx_busy_reg = 0;
    reg tx_reg = 1;
    assign tx_pin = tx_reg;

    // UART RX module
    reg rx_sync_0 = 1, rx_sync_1 = 1, rx_sync_2 = 1;
    reg [3:0] rx_bitnum = 0;
    reg [15:0] rx_cnt = 0;
    reg [7:0] rx_shifter = 0;
    reg rx_active = 0;
    reg rx_ready_reg = 0;
    reg [7:0] rx_data_reg = 0;

    assign rx_data = rx_data_reg;
    assign rx_ready = rx_ready_reg;

    // Packet for handshake (as per R307S datasheet)
    initial begin
        handshake_pkt[0] = 8'hEF; // header
        handshake_pkt[1] = 8'h01;
        handshake_pkt[2] = 8'hFF; // address
        handshake_pkt[3] = 8'hFF;
        handshake_pkt[4] = 8'hFF;
        handshake_pkt[5] = 8'hFF;
        handshake_pkt[6] = 8'h01; // packet identifier
        handshake_pkt[7] = 8'h00; // length high
        handshake_pkt[8] = 8'h03; // length low
        handshake_pkt[9] = 8'h01; // command: handshake
        handshake_pkt[10]= 8'h00;
        handshake_pkt[11]= 8'h05; // checksum: 1+3+1=5 (adjust if needed)
    end

    // MAIN STATE MACHINE
    always @(posedge clk) begin
        if (rst) begin
            counter <= 0;
            state   <= 0;
            pkt_idx <= 0;
            tx_start <= 0;
            led_reg <= 0;
        end else begin
            // Blink LED on RX
            if (rx_ready_reg)
                led_reg <= ~led_reg;
            case (state)
                0: begin // Idle: wait for 3sec
                    if (counter >= 300_000_000) begin // 3s at 100MHz
                        counter <= 0;
                        pkt_idx <= 0;
                        state <= 1;
                    end else begin
                        counter <= counter + 1;
                    end
                    tx_start <= 0;
                end
                1: begin // Start UART TX for handshake byte
                    if (!tx_busy_reg) begin
                        tx_data <= handshake_pkt[pkt_idx];
                        tx_start <= 1;
                        state <= 2;
                    end
                end
                2: begin // Clear start flag, start UART byte
                    tx_start <= 0;
                    if (tx_busy_reg) state <= 3;
                end
                3: begin // Wait for TX to finish
                    if (!tx_busy_reg) begin
                        if (pkt_idx < 11) begin
                            pkt_idx <= pkt_idx + 1;
                            state <= 1;
                        end else begin
                            state <= 0;
                        end
                    end
                end
            endcase
        end
    end

    // UART TX (bitbanged inside always block for resource sharing)
    always @(posedge clk) begin
        if (rst) begin
            tx_active <= 0;
            tx_bitnum <= 0;
            tx_busy_reg <= 0;
            tx_cnt <= 0;
            tx_shifter <= 10'b1111111111;
            tx_reg <= 1;
        end else begin
            if (tx_start && !tx_active) begin
                tx_shifter <= {1'b1, tx_data, 1'b0}; // stop, data, start
                tx_bitnum <= 0;
                tx_cnt <= 0;
                tx_reg <= 0;
                tx_active <= 1;
                tx_busy_reg <= 1;
            end else if (tx_active) begin
                if (tx_cnt >= TICKS-1) begin
                    tx_cnt <= 0;
                    tx_bitnum <= tx_bitnum + 1;
                    tx_shifter <= {1'b1, tx_shifter[9:1]};
                    tx_reg <= tx_shifter[1];
                    if (tx_bitnum == 9) begin
                        tx_active <= 0;
                        tx_busy_reg <= 0;
                        tx_reg <= 1;
                    end
                end else begin
                    tx_cnt <= tx_cnt + 1;
                end
            end
        end
    end

    // UART RX (bitbanged inside always block)
    always @(posedge clk) begin
        // Synchronize RX
        rx_sync_0 <= rx_pin;
        rx_sync_1 <= rx_sync_0;
        rx_sync_2 <= rx_sync_1;
        if (rst) begin
            rx_active <= 0;
            rx_bitnum <= 0;
            rx_cnt <= 0;
            rx_shifter <= 0;
            rx_ready_reg <= 0;
        end else if (~rx_active && ~rx_sync_2) begin // Start bit
            rx_active <= 1;
            rx_cnt <= TICKS/2;
            rx_bitnum <= 0;
            rx_ready_reg <= 0;
        end else if (rx_active) begin
            if (rx_cnt >= TICKS-1) begin
                rx_cnt <= 0;
                if (rx_bitnum < 8) begin
                    rx_shifter[rx_bitnum] <= rx_sync_2;
                    rx_bitnum <= rx_bitnum + 1;
                end else begin
                    rx_data_reg <= rx_shifter;
                    rx_ready_reg <= 1;
                    rx_active <= 0;
                end
            end else begin
                rx_cnt <= rx_cnt + 1;
            end
        end else begin
            rx_ready_reg <= 0;
        end
    end

endmodule