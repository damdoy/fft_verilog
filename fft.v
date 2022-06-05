module fft(clk, data_in, wr_en, data_out, next_data_rd, busy, start);

/* verilator lint_off WIDTH */
/* verilator lint_off BLKSEQ */

//three parameters defining the FFT module
parameter INT_WIDTH = 8;
parameter FRAC_WIDTH = 12;
parameter FFT_WIDTH = 6;


parameter BIT_WIDTH = (INT_WIDTH+FRAC_WIDTH);
parameter FFT_SIZE = (2**FFT_WIDTH);
parameter MEM_SIZE = FFT_SIZE-1;

input wire clk;
input wire [BIT_WIDTH-1:0] data_in;
input wire wr_en;
output reg [BIT_WIDTH-1:0] data_out;
input wire next_data_rd;
input wire start;
output reg busy;

reg [FFT_WIDTH-1:0] cur_wr_addr;
var [FFT_WIDTH-1:0] cur_wr_addr_calc;
reg [FFT_WIDTH:0] cur_rd_addr; //add a bit as MSB for the real/imag selection
var [FFT_WIDTH:0] cur_rd_addr_calc;

reg running;
reg [7:0] fft_cur_stage;

var [FFT_WIDTH-1:0] mem_addr_calc_first;
var [FFT_WIDTH-1:0] mem_addr_calc_second;
var [FFT_WIDTH-1:0] w_addr_calc;

var [BIT_WIDTH*2:0] mult_calc;
var [BIT_WIDTH*2:0] bit_ext_mem_re;
var [BIT_WIDTH*2:0] bit_ext_mem_imag;
var [BIT_WIDTH*2:0] bit_ext_cos;
var [BIT_WIDTH*2:0] bit_ext_sin;

//have an array for the real and imaginary part
//duplicate the arrays to have two steps of the fft at any point
reg [BIT_WIDTH-1:0] mem_real [0:MEM_SIZE];
reg [BIT_WIDTH-1:0] mem_real_sec [0:MEM_SIZE];
reg [BIT_WIDTH-1:0] mem_imag [0:MEM_SIZE];
reg [BIT_WIDTH-1:0] mem_imag_sec [0:MEM_SIZE];

reg [FFT_WIDTH-1:0] mem_idx_counter;

wire [BIT_WIDTH-1:0] W_weights_cos [0:MEM_SIZE];
wire [BIT_WIDTH-1:0] W_weights_sin [0:MEM_SIZE];
genvar gi;

initial begin
    cur_wr_addr = 0;
    cur_rd_addr = 0;

    running = 0;
    fft_cur_stage = 0;

end

//generating arrays of cos and sin for the selected size of fft
//careful int' seems to be 32bits
generate
    for(gi=0; gi<MEM_SIZE+1; gi=gi+1) begin:generate_w
        assign W_weights_cos[gi] = int'( $cos(gi*2*3.141592/$itor(FFT_SIZE) )*(1<<FRAC_WIDTH) );
        assign W_weights_sin[gi] = int'( $sin(gi*2*3.141592/$itor(FFT_SIZE) )*(1<<FRAC_WIDTH) );
    end
endgenerate



always @(posedge clk)
begin
    busy <= 0;
    //depending on the width of fft, will output final data from the 1st or 2nd mem array
    if(FFT_WIDTH[0] == 0) begin
        data_out <= cur_rd_addr[FFT_WIDTH]? mem_imag[cur_rd_addr] : mem_real[cur_rd_addr];
    end else begin
        data_out <= cur_rd_addr[FFT_WIDTH]? mem_imag_sec[cur_rd_addr] : mem_real_sec[cur_rd_addr];
    end

    if(wr_en == 1) begin
        //inverse address bits to place the elements in the FFT array
        for(int i = 0; i < FFT_WIDTH; i++) begin
            cur_wr_addr_calc[FFT_WIDTH-1-i] = cur_wr_addr[i];
        end
        mem_real[cur_wr_addr_calc] <= data_in;
        mem_imag[cur_wr_addr_calc] <= 0;
        cur_wr_addr <= cur_wr_addr+1;
    end


    if(next_data_rd == 1) begin
        cur_rd_addr_calc = cur_rd_addr+1;
        //depending on the width of fft, will output final data from the 1st or 2nd mem array
        if(FFT_WIDTH[0] == 0) begin
            data_out <= cur_rd_addr_calc[FFT_WIDTH]? mem_imag[cur_rd_addr_calc] : mem_real[cur_rd_addr_calc];
        end else begin
            data_out <= cur_rd_addr_calc[FFT_WIDTH]? mem_imag_sec[cur_rd_addr_calc] : mem_real_sec[cur_rd_addr_calc];
        end
        cur_rd_addr <= cur_rd_addr+1;
    end

    if(start == 1) begin
        running <= 1;
        fft_cur_stage <= 0;
        busy <= 1;
        mem_idx_counter <= 0;
    end

    if(running == 1) begin
        busy <= 1;

        mem_addr_calc_first = mem_idx_counter;
        mem_addr_calc_first[fft_cur_stage] = 0;
        mem_addr_calc_second = mem_idx_counter;
        mem_addr_calc_second[fft_cur_stage] = 1;
        w_addr_calc = 0;

        // translation for w_addr_calc[FFT_WIDTH-1:FFT_WIDTH-1-fft_cur_stage] = mem_idx_counter[fft_cur_stage:0];
        for(int i = 0; i < FFT_WIDTH; i++) begin
            if(i <= fft_cur_stage) begin
                w_addr_calc[FFT_WIDTH-1-fft_cur_stage+i] = mem_idx_counter[i];
            end
        end

        //use the two arrays, one as input the other as output depending on the stage
        if(fft_cur_stage[0] == 0) begin
            //extend the sign bit for the multiplication of fixed numbers
            bit_ext_mem_re = { {BIT_WIDTH{mem_real[ mem_addr_calc_second ][BIT_WIDTH-1]}}, mem_real[ mem_addr_calc_second ]};
            bit_ext_mem_imag = { {BIT_WIDTH{mem_imag[ mem_addr_calc_second ][BIT_WIDTH-1]}}, mem_imag[ mem_addr_calc_second ]};
            bit_ext_cos = { {BIT_WIDTH{W_weights_cos[w_addr_calc][BIT_WIDTH-1]}}, W_weights_cos[w_addr_calc]};
            bit_ext_sin = { {BIT_WIDTH{W_weights_sin[w_addr_calc][BIT_WIDTH-1]}}, W_weights_sin[w_addr_calc]};

            //// real calc
            mult_calc = (bit_ext_cos*bit_ext_mem_re)>>FRAC_WIDTH;
            mult_calc = mult_calc+((bit_ext_sin*bit_ext_mem_imag)>>FRAC_WIDTH);

            mem_real_sec[mem_idx_counter] <= mem_real[mem_addr_calc_first]+mult_calc;

            //// imag calc
            mult_calc = (bit_ext_cos*bit_ext_mem_imag)>>FRAC_WIDTH;
            mult_calc = mult_calc-((bit_ext_sin*bit_ext_mem_re)>>FRAC_WIDTH);
            mem_imag_sec[mem_idx_counter] <= mem_imag[mem_addr_calc_first]+mult_calc;

        end else begin
            bit_ext_mem_re = { {BIT_WIDTH{mem_real_sec[ mem_addr_calc_second ][BIT_WIDTH-1]}}, mem_real_sec[ mem_addr_calc_second ]};
            bit_ext_mem_imag = { {BIT_WIDTH{mem_imag_sec[ mem_addr_calc_second ][BIT_WIDTH-1]}}, mem_imag_sec[ mem_addr_calc_second ]};
            bit_ext_cos = { {BIT_WIDTH{W_weights_cos[w_addr_calc][BIT_WIDTH-1]}}, W_weights_cos[w_addr_calc]};
            bit_ext_sin = { {BIT_WIDTH{W_weights_sin[w_addr_calc][BIT_WIDTH-1]}}, W_weights_sin[w_addr_calc]};

            //// real calc
            mult_calc = (bit_ext_cos*bit_ext_mem_re)>>FRAC_WIDTH;
            mult_calc = mult_calc+((bit_ext_sin*bit_ext_mem_imag)>>FRAC_WIDTH);

            mem_real[mem_idx_counter] <= mem_real_sec[mem_addr_calc_first]+mult_calc;

            //// imag calc
            mult_calc = (bit_ext_cos*bit_ext_mem_imag)>>FRAC_WIDTH;
            mult_calc = mult_calc-((bit_ext_sin*bit_ext_mem_re)>>FRAC_WIDTH);

            mem_imag[mem_idx_counter] <= mem_imag_sec[mem_addr_calc_first]+mult_calc;

        end

        mem_idx_counter <= mem_idx_counter+1;

        if(mem_idx_counter == MEM_SIZE) begin
            mem_idx_counter <= 0;
            fft_cur_stage <= fft_cur_stage+1;
            if(fft_cur_stage+1 == FFT_WIDTH) begin
                fft_cur_stage <= 0;
                running <= 0;
            end
        end
    end
end

endmodule
