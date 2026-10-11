module tt_um_sine_area_detector_v6 #(
    parameter integer HANDOFF_WAIT_CYCLES = 80000
) (
    input  wire [7:0] ui_in,//8-bit ADC code
    output wire [7:0] uo_out,//Low 8 bits of area or peak
    input  wire [7:0] uio_in,//uio[4:0]: level before latching
    output wire [7:0] uio_out,//uio[7:5]: upper result bits; uio[0]: result type
    output wire [7:0] uio_oe,//uio[0] becomes an output after handoff
    /* Retained for template compatibility; operation ignores ena. */
    input  wire       ena,
    input  wire       clk,//80 MHz
    input  wire       rst_n
);

    wire _unused = &{ena, 1'b0};

    /* Configuration and division: latch once, then wait a full interval. */
    /* Convert the ADC code to a binary sign. */
    wire adc_sign;
    assign adc_sign = (ui_in >= 8'h80);

    /* Levels 0-23: binary division; level 23: about 4.6566 mHz at 80 MHz. */
    reg [4:0] config_level;
    reg       config_valid;

    always @* begin
        config_level = uio_in[4:0];
        config_valid     = 1'b0;

        if (uio_in[4:0] <= 5'd23)
            config_valid = 1'b1;
    end

    wire square_wave;
    wire overlap_bit;
    assign overlap_bit = adc_sign == square_wave;

    /* Latch the first valid level after reset. */
    reg       config_latched_valid;

    /*
     * Sample every 2^level clocks, including level 23.
     */
    reg  [26:0] prescale_count;
    wire        divider_expired;

    /* Decode once on the configuration edge; preserve the first sample. */
    reg [26:0] prescale_terminal_latched;
    wire [26:0] config_terminal;
    assign config_terminal =
        (27'd1 << config_level) - 27'd1;
    assign divider_expired =
        (prescale_count == prescale_terminal_latched);

    /* Sampling pipeline: capture ADC and its reference phase together at N.
     * The backend consumes this saved sample at N+1. */
    reg sample_valid;
    reg [7:0] sample_magnitude;
    reg sample_overlap;
    reg [10:0] sample_position;
    reg stats_reset;

    /* Area statistics: count ones in the last 2048 overlap samples. */
    reg [2047:0] overlap_history;
    reg [10:0] history_pointer;
    reg [11:0] running_sum;
    reg        window_full;
    /* Independent square wave */
    assign square_wave = history_pointer[10];

    wire        oldest_overlap;
    wire        effective_oldest_overlap;
    wire [11:0] slide_sum_next;

    assign oldest_overlap = overlap_history[2047];
    /* Unwritten history counts as zero. */
    assign effective_oldest_overlap = window_full ? oldest_overlap : 1'b0;
    assign slide_sum_next =
        ( sample_overlap && !effective_oldest_overlap) ? (running_sum + 12'd1) :
        (!sample_overlap &&  effective_oldest_overlap) ? (running_sum - 12'd1) :
                                            running_sum;

    /* Absolute ADC distance from middle. */
    wire [7:0] adc_magnitude;
    assign adc_magnitude = ui_in[7] ? (ui_in - 8'd128) : (8'd128 - ui_in);

    /* Peak candidates: two ranked candidates and the previous processed sample. */
    reg [7:0] peak_first;
    reg [7:0] peak_second;
    reg [7:0] peak_buffer;
    reg [9:0] peak_first_position;
    reg [9:0] peak_second_position;
    reg [9:0] peak_buffer_position;
    /* First candidate and buffer become valid on the same processing edge.
     * Candidate expiry is checked separately by first_alive/second_alive. */
    reg peak_history_valid;
    reg peak_second_valid;

    reg [7:0] peak_first_next;
    reg [7:0] peak_second_next;
    reg [9:0] peak_first_position_next;
    reg [9:0] peak_second_position_next;
    reg peak_second_valid_next;
    wire take_sample;
    assign take_sample = config_latched_valid && divider_expired;

    /* Survival checks and parallel magnitude comparisons. */
    wire first_alive;
    wire second_alive;
    wire buffer_diff_first;
    wire buffer_diff_second;
    wire new_ge_first;
    wire new_ge_second;
    wire new_ge_buffer;
    wire fill_second;
    wire new_is_first;
    wire new_is_second;
    wire first_from_first;
    wire first_from_second;
    wire second_from_first;
    wire second_from_second;
    wire second_from_buffer;

    assign first_alive = peak_history_valid &&
        (peak_first_position != sample_position[9:0]);
    assign second_alive = peak_second_valid &&
        (peak_second_position != sample_position[9:0]);
    assign buffer_diff_first = peak_buffer_position != peak_first_position;
    assign buffer_diff_second = peak_buffer_position != peak_second_position;
    assign new_ge_first = (sample_magnitude >= peak_first);
    assign new_ge_second = (sample_magnitude >= peak_second);
    assign new_ge_buffer = (sample_magnitude >= peak_buffer);

    /* Refill only an empty second slot, without duplicating the survivor. */
    assign fill_second = !(first_alive && second_alive) && peak_history_valid &&
        ((first_alive && buffer_diff_first) ||
         (!first_alive && (!second_alive || buffer_diff_second)));
    /* Decide whether the new sample enters slot one or two; ties favor new. */
    assign new_is_first = !(first_alive || second_alive) ||
        (first_alive && new_ge_first) ||
        (!first_alive && second_alive && new_ge_second);
    assign new_is_second = !new_is_first &&
        (!((first_alive && second_alive) || fill_second) ||
         (fill_second && new_ge_buffer) ||
         (!fill_second && new_ge_second));

    /* Mutually exclusive selectors keep values and positions paired. */
    assign first_from_first = !new_is_first && first_alive;
    assign first_from_second = !new_is_first && !first_alive;
    assign second_from_first = new_is_first && first_alive;
    assign second_from_second = (new_is_first && !first_alive) ||
        (!new_is_first && !new_is_second && !fill_second);
    assign second_from_buffer = !new_is_first && !new_is_second && fill_second;

    /* Select each value and position from the same source. */
    always @* begin
        peak_first_next = ({8{new_is_first}} & sample_magnitude) |
            ({8{first_from_first}} & peak_first) |
            ({8{first_from_second}} & peak_second);
        peak_first_position_next = ({10{new_is_first}} & sample_position[9:0]) |
            ({10{first_from_first}} & peak_first_position) |
            ({10{first_from_second}} & peak_second_position);

        peak_second_next = ({8{new_is_second}} & sample_magnitude) |
            ({8{second_from_first}} & peak_first) |
            ({8{second_from_second}} & peak_second) |
            ({8{second_from_buffer}} & peak_buffer);
        peak_second_position_next = ({10{new_is_second}} & sample_position[9:0]) |
            ({10{second_from_first}} & peak_first_position) |
            ({10{second_from_second}} & peak_second_position) |
            ({10{second_from_buffer}} & peak_buffer_position);
        peak_second_valid_next = new_is_first ? (first_alive || second_alive) :
            ((first_alive && second_alive) || fill_second || new_is_second);
    end

    /* Output handoff: wait 1 ms at 80 MHz before driving uio[0]. */
    localparam integer HANDOFF_CYCLES =
        (HANDOFF_WAIT_CYCLES < 1) ? 1 : HANDOFF_WAIT_CYCLES;
    /* Up to 131072 clocks. */
    localparam [16:0] HANDOFF_LAST = HANDOFF_CYCLES - 1;
    reg [16:0] handoff_count;
    reg output_ready;
    /* Register data and its type on the same edge. */
    wire [10:0] area_latest;
    reg [10:0] output_data;
    reg output_kind;
    wire send_peak;
    assign area_latest = running_sum[11] ? 11'd2047 : running_sum[10:0];
    // Keep the output selector known during reset.
    assign send_peak = rst_n && output_ready && !output_kind;
    /* Flat branch guards preserve the original procedural if/else rules.
     * An if takes its true branch only for a known one. Case comparisons
     * against known constants keep the old else behavior for X/Z controls. */
    wire frontend_run;
    wire backend_process;
    wire handoff_active;
    wire handoff_due;
    assign frontend_run = (rst_n !== 1'b0);
    assign backend_process = (stats_reset !== 1'b1) && sample_valid;
    assign handoff_active = frontend_run && config_latched_valid && !output_ready;
    assign handoff_due = (handoff_count == HANDOFF_LAST);

    /* Counter updates: one assignment with reset, increment, hold priority.
     * Case comparisons preserve the original if behavior for X/Z enables. */
    wire history_count_enable;
    wire handoff_count_enable;
    assign history_count_enable =
        ((frontend_run && take_sample) === 1'b1);
    assign handoff_count_enable =
        ((handoff_active && (handoff_due !== 1'b1)) === 1'b1);

    always @(posedge clk) begin
        history_pointer <=
            (rst_n === 1'b0) ? 11'd0 :
            history_count_enable ? history_pointer + 11'd1 : history_pointer;
        handoff_count <=
            (rst_n === 1'b0) ? 17'd0 :
            handoff_count_enable ? handoff_count + 17'd1 : handoff_count;
    end

    /* Sequential updates: reset and each update have disjoint flat guards.
     * Outputs read old backend state: a sample can appear from N+2. */
    always @(posedge clk) begin
        stats_reset <= !rst_n;

        if (!rst_n) begin
            config_latched_valid <= 1'b0;
            prescale_terminal_latched <= 27'd0;
            prescale_count <= 27'd0;
            sample_valid <= 1'b0;
            sample_magnitude <= 8'd0;
            sample_overlap <= 1'b0;
            sample_position <= 11'd0;
            output_ready <= 1'b0;
            output_data <= 11'd0;
            output_kind <= 1'b0;
        end

        if (frontend_run && !config_latched_valid && config_valid) begin
            prescale_terminal_latched <= config_terminal;
            config_latched_valid <= 1'b1;
        end

        if (frontend_run && config_latched_valid)
            prescale_count <= divider_expired ? 27'd0 : prescale_count + 27'd1;

        if (frontend_run && take_sample) begin
            sample_magnitude <= adc_magnitude;
            sample_overlap <= overlap_bit;
            sample_position <= history_pointer;
        end

        if (handoff_active && handoff_due)
            output_ready <= 1'b1;

        if (frontend_run) begin
            sample_valid <= take_sample;
            output_kind <= send_peak;
            /* Hide old statistics while the delayed reset clears them. */
            output_data <= stats_reset ? 11'd0 :
                (send_peak ? {3'b000, peak_first} : area_latest);
        end
    end

    /* Area state has one assignment with reset, process, hold priority.
     * Known-one guards preserve the procedural behavior for X/Z controls. */
    always @(posedge clk) begin
        running_sum <=
            (stats_reset === 1'b1) ? 12'd0 :
            ((backend_process === 1'b1) ? slide_sum_next : running_sum);
    end

    /* Backend reset and processing are mutually exclusive, including X/Z.
     * History bits are not reset; window_full masks unwritten entries. */
    always @(posedge clk) begin
        if (stats_reset) begin
            window_full <= 1'b0;
            peak_first <= 8'd0;
            peak_second <= 8'd0;
            peak_buffer <= 8'd0;
            peak_first_position <= 10'd0;
            peak_second_position <= 10'd0;
            peak_buffer_position <= 10'd0;
            peak_history_valid <= 1'b0;
            peak_second_valid <= 1'b0;
        end

        if (backend_process) begin
            overlap_history <= {overlap_history[2046:0], sample_overlap};
            peak_first <= peak_first_next;
            peak_second <= peak_second_next;
            peak_buffer <= sample_magnitude;
            peak_first_position <= peak_first_position_next;
            peak_second_position <= peak_second_position_next;
            peak_buffer_position <= sample_position[9:0];
            peak_history_valid <= 1'b1;
            peak_second_valid <= peak_second_valid_next;
        end

        if (backend_process && (sample_position == 11'd2047))
            window_full <= 1'b1;
    end

    /* Type 0: area; type 1: peak. */
    assign uo_out  = output_data[7:0];
    assign uio_out = {output_data[10:8], 4'b0000, output_kind};
    assign uio_oe  = output_ready ? 8'he1 : 8'he0;

endmodule
