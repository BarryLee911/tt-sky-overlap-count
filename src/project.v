module tt_um_sine_area_detector #(
    parameter integer HANDOFF_WAIT_CYCLES = 80000
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire _unused = &{ena, 1'b0};

    wire adc_sign;
    assign adc_sign = (ui_in >= 8'h80);

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

    reg       config_latched_valid;

    reg  [26:0] prescale_count;

    reg [26:0] prescale_terminal_latched;
    wire [26:0] config_terminal;
    assign config_terminal =
        (27'd1 << config_level) - 27'd1;

    reg         take_sample_q;
    wire [26:0] prescale_terminal_m1;
    wire        take_sample_d;
    assign prescale_terminal_m1 = {
        prescale_terminal_latched[26:1] | {26{~prescale_terminal_latched[0]}},
        ~prescale_terminal_latched[0]};

    wire [31:0] count_is_terminal;
    genvar terminal_level;
    generate
        for (terminal_level = 0; terminal_level < 32; terminal_level = terminal_level + 1) begin : g_terminal
            if (terminal_level < 24) begin : g_legal
                assign count_is_terminal[terminal_level] =
                    (prescale_count == ((27'd1 << terminal_level) - 27'd1));
            end else begin : g_illegal
                assign count_is_terminal[terminal_level] = 1'b0;
            end
        end
    endgenerate
    assign take_sample_d =
        !config_latched_valid ?
            (config_valid && count_is_terminal[config_level]) :
        take_sample_q ?
            ~prescale_terminal_latched[0] :
            (prescale_count == prescale_terminal_m1);

    reg sample_valid;
    reg [7:0] sample_magnitude;
    reg sample_overlap;
    reg [10:0] sample_position;
    reg stats_reset;

    reg [2047:0] overlap_history;
    reg [10:0] history_pointer;
    reg [11:0] running_sum;
    reg        window_full;

    assign square_wave = history_pointer[10];

    wire        oldest_overlap;
    wire        effective_oldest_overlap;
    wire [11:0] slide_sum_next;

    assign oldest_overlap = overlap_history[2047];

    assign effective_oldest_overlap = window_full ? oldest_overlap : 1'b0;
    assign slide_sum_next =
        ( sample_overlap && !effective_oldest_overlap) ? (running_sum + 12'd1) :
        (!sample_overlap &&  effective_oldest_overlap) ? (running_sum - 12'd1) :
                                            running_sum;

    wire [7:0] adc_magnitude;
    assign adc_magnitude = ui_in[7] ? (ui_in - 8'd128) : (8'd128 - ui_in);

    reg [7:0] peak_first;
    reg [7:0] peak_second;
    reg [7:0] peak_buffer;
    reg [9:0] peak_first_position;
    reg [9:0] peak_second_position;
    reg [9:0] peak_buffer_position;

    reg peak_history_valid;
    reg peak_second_valid;

    reg [7:0] peak_first_next;
    reg [7:0] peak_second_next;
    reg [9:0] peak_first_position_next;
    reg [9:0] peak_second_position_next;
    reg peak_second_valid_next;
    wire take_sample;
    assign take_sample = take_sample_q;

    reg first_alive_q;
    reg second_alive_q;
    reg buffer_diff_first_q;
    reg buffer_diff_second_q;
    reg new_ge_first_q;
    reg new_ge_second_q;
    reg new_ge_buffer_q;

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

    assign first_alive = first_alive_q;
    assign second_alive = second_alive_q;
    assign buffer_diff_first = buffer_diff_first_q;
    assign buffer_diff_second = buffer_diff_second_q;
    assign new_ge_first = new_ge_first_q;
    assign new_ge_second = new_ge_second_q;
    assign new_ge_buffer = new_ge_buffer_q;

    assign fill_second = !(first_alive && second_alive) && peak_history_valid &&
        ((first_alive && buffer_diff_first) ||
         (!first_alive && (!second_alive || buffer_diff_second)));

    assign new_is_first = !(first_alive || second_alive) ||
        (first_alive && new_ge_first) ||
        (!first_alive && second_alive && new_ge_second);
    assign new_is_second = !new_is_first &&
        (!((first_alive && second_alive) || fill_second) ||
         (fill_second && new_ge_buffer) ||
         (!fill_second && new_ge_second));

    assign first_from_first = !new_is_first && first_alive;
    assign first_from_second = !new_is_first && !first_alive;
    assign second_from_first = new_is_first && first_alive;
    assign second_from_second = (new_is_first && !first_alive) ||
        (!new_is_first && !new_is_second && !fill_second);
    assign second_from_buffer = !new_is_first && !new_is_second && fill_second;

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

    wire [9:0] incoming_position;
    wire       stats_clearing;
    wire       backend_process;
    assign incoming_position = history_pointer[9:0];

    function magnitude_ge;
        input [7:0] code;
        input [7:0] x;
        reg   [8:0] upper;
        reg   [8:0] lower;
        begin
            upper = 9'd128 + {1'b0, x};
            lower = 9'd128 - {1'b0, x};
            magnitude_ge = ({1'b0, code} >= upper) ||
                ((x <= 8'd128) && ({1'b0, code} <= lower));
        end
    endfunction
    wire in_ge_current = magnitude_ge(ui_in, sample_magnitude);
    wire in_ge_first   = magnitude_ge(ui_in, peak_first);
    wire in_ge_second  = magnitude_ge(ui_in, peak_second);
    wire in_ge_buffer  = magnitude_ge(ui_in, peak_buffer);
    wire in_ne_current = (incoming_position != sample_position[9:0]);
    wire in_ne_first   = (incoming_position != peak_first_position);
    wire in_ne_second  = (incoming_position != peak_second_position);
    wire in_ne_buffer  = (incoming_position != peak_buffer_position);

    wire cur_ne_first  = (sample_position[9:0] != peak_first_position);
    wire cur_ne_second = (sample_position[9:0] != peak_second_position);
    wire cur_ne_buffer = (sample_position[9:0] != peak_buffer_position);
    wire buf_ne_first  = (peak_buffer_position != peak_first_position);
    wire buf_ne_second = (peak_buffer_position != peak_second_position);

    wire first_alive_d;
    wire second_alive_d;
    wire buffer_diff_first_d;
    wire buffer_diff_second_d;
    wire new_ge_first_d;
    wire new_ge_second_d;
    wire new_ge_buffer_d;

    assign first_alive_d =
        stats_clearing ? 1'b0 :
        backend_process ?
            ((new_is_first && in_ne_current) ||
             (first_from_first && in_ne_first) ||
             (first_from_second && in_ne_second)) :
            (peak_history_valid && in_ne_first);
    assign second_alive_d =
        stats_clearing ? 1'b0 :
        backend_process ?
            (peak_second_valid_next &&
             ((new_is_second && in_ne_current) ||
              (second_from_first && in_ne_first) ||
              (second_from_second && in_ne_second) ||
              (second_from_buffer && in_ne_buffer))) :
            (peak_second_valid && in_ne_second);
    assign buffer_diff_first_d =
        stats_clearing ? 1'b0 :
        backend_process ?
            ((first_from_first && cur_ne_first) ||
             (first_from_second && cur_ne_second)) :
            buf_ne_first;
    assign buffer_diff_second_d =
        stats_clearing ? 1'b0 :
        backend_process ?
            ((second_from_first && cur_ne_first) ||
             (second_from_second && cur_ne_second) ||
             (second_from_buffer && cur_ne_buffer)) :
            buf_ne_second;
    assign new_ge_first_d =
        stats_clearing ? 1'b1 :
        backend_process ?
            ((new_is_first && in_ge_current) ||
             (first_from_first && in_ge_first) ||
             (first_from_second && in_ge_second)) :
            in_ge_first;
    assign new_ge_second_d =
        stats_clearing ? 1'b1 :
        backend_process ?
            ((new_is_second && in_ge_current) ||
             (second_from_first && in_ge_first) ||
             (second_from_second && in_ge_second) ||
             (second_from_buffer && in_ge_buffer)) :
            in_ge_second;
    assign new_ge_buffer_d =
        stats_clearing ? 1'b1 :
        backend_process ? in_ge_current : in_ge_buffer;

    localparam integer HANDOFF_CYCLES =
        (HANDOFF_WAIT_CYCLES < 1) ? 1 : HANDOFF_WAIT_CYCLES;

    localparam [16:0] HANDOFF_LAST = HANDOFF_CYCLES - 1;
    reg [16:0] handoff_count;
    reg output_ready;

    wire [10:0] area_latest;
    reg [10:0] output_data;
    reg output_kind;
    wire send_peak;
    assign area_latest = running_sum[11] ? 11'd2047 : running_sum[10:0];

    assign send_peak = rst_n && output_ready && !output_kind;

    wire frontend_run;
    wire handoff_active;
    wire handoff_due;
    assign frontend_run = (rst_n !== 1'b0);
    assign backend_process = (stats_reset !== 1'b1) && sample_valid;
    assign stats_clearing = (stats_reset === 1'b1);
    assign handoff_active = frontend_run && config_latched_valid && !output_ready;
    assign handoff_due = (handoff_count == HANDOFF_LAST);

    wire history_count_enable;
    wire handoff_count_enable;
    assign history_count_enable =
        ((frontend_run && take_sample) === 1'b1);
    assign handoff_count_enable =
        ((handoff_active && (handoff_due !== 1'b1)) === 1'b1);

    always @(posedge clk) begin
        prescale_count <=
            (rst_n === 1'b0) ? 27'd0 :
            ((frontend_run && config_latched_valid) === 1'b1) ?
                (take_sample_q ? 27'd0 : prescale_count + 27'd1) :
                prescale_count;
        history_pointer <=
            (rst_n === 1'b0) ? 11'd0 :
            history_count_enable ? history_pointer + 11'd1 : history_pointer;
        handoff_count <=
            (rst_n === 1'b0) ? 17'd0 :
            handoff_count_enable ? handoff_count + 17'd1 : handoff_count;
    end

    always @(posedge clk) begin
        stats_reset <= !rst_n;

        if (!rst_n) begin
            config_latched_valid <= 1'b0;
            prescale_terminal_latched <= 27'd0;
            take_sample_q <= 1'b0;
            sample_valid <= 1'b0;
            sample_magnitude <= 8'd0;
            sample_overlap <= 1'b0;
            sample_position <= 11'd0;
            first_alive_q <= 1'b0;
            second_alive_q <= 1'b0;
            buffer_diff_first_q <= 1'b0;
            buffer_diff_second_q <= 1'b0;
            new_ge_first_q <= 1'b1;
            new_ge_second_q <= 1'b1;
            new_ge_buffer_q <= 1'b1;
            output_ready <= 1'b0;
            output_data <= 11'd0;
            output_kind <= 1'b0;
        end

        if (frontend_run && !config_latched_valid && config_valid) begin
            prescale_terminal_latched <= config_terminal;
            config_latched_valid <= 1'b1;
        end

        if (frontend_run)
            take_sample_q <= take_sample_d;

        if (frontend_run && take_sample) begin
            sample_magnitude <= adc_magnitude;
            sample_overlap <= overlap_bit;
            sample_position <= history_pointer;
            first_alive_q <= first_alive_d;
            second_alive_q <= second_alive_d;
            buffer_diff_first_q <= buffer_diff_first_d;
            buffer_diff_second_q <= buffer_diff_second_d;
            new_ge_first_q <= new_ge_first_d;
            new_ge_second_q <= new_ge_second_d;
            new_ge_buffer_q <= new_ge_buffer_d;
        end

        if (handoff_active && handoff_due)
            output_ready <= 1'b1;

        if (frontend_run) begin
            sample_valid <= take_sample;
            output_kind <= send_peak;

            output_data <= stats_reset ? 11'd0 :
                (send_peak ? {3'b000, peak_first} : area_latest);
        end
    end

    always @(posedge clk) begin
        running_sum <=
            (stats_reset === 1'b1) ? 12'd0 :
            ((backend_process === 1'b1) ? slide_sum_next : running_sum);
    end

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

    assign uo_out  = output_data[7:0];
    assign uio_out = {output_data[10:8], 4'b0000, output_kind};
    assign uio_oe  = output_ready ? 8'he1 : 8'he0;

endmodule
`default_nettype none
module tt_um_barrylee911_sine_area_v6 (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena,
    input wire clk,
    input wire rst_n
);
    tt_um_sine_area_detector core (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );
endmodule
`default_nettype wire
