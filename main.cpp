#include <stdlib.h>
#include <iostream>
#include <cstring>
#include <string>
#include <fstream>
#include <vector>
#include <elf.h>
#include "Vfft.h"
#include "verilated.h"

//bit sizes for the fixed point representation
#define SIZE_INTEGER 8
#define MASK_INTEGER ((1<<SIZE_INTEGER)-1)
#define SIZE_FRAC 12
#define MASK_FRAC ((1<<SIZE_FRAC)-1)
#define MASK_INTEGER_SHIFTED (MASK_INTEGER<<SIZE_FRAC)

//will define the size of the FPGA FFT module, needs to be the same as the FPGA module
#define FFT_ELEMENTS 64

#define VERBOSE 0

void write_val(Vfft *tb, float val)
{
    //we want the first SIZE_INTEGER bits to be part for the integer, then SIZE_FRAC bits for the fractional part
    double decimal = 0;
    float val_abs = abs(val);
    float frac = modf(val_abs, &decimal);
    uint32_t val_i = 0;
    val_i += (((uint)decimal)&MASK_INTEGER)<<SIZE_FRAC;
    int frac_shift = (1<<SIZE_FRAC); //if size_frac is 4, then the float mult/shift will be 16, to bring it in integer range
    val_i += ((uint)(frac*frac_shift))&MASK_FRAC;

    //if negative, we need to reverse the bits
    if(val < 0){
        val_i = ~val_i & (MASK_INTEGER_SHIFTED|MASK_FRAC);
    }

    #if VERBOSE
        printf("val_f: %f, fixed_point: 0x%x\n\r", val, val_i);
    #endif

    tb->clk = 0;
    tb->eval();
    tb->clk = 1;
    tb->data_in = val_i;
    tb->wr_en = 1;
    tb->eval();
    tb->data_in = 0;
    tb->wr_en = 0;
}

float get_val(Vfft *tb)
{
    uint32_t val_i = tb->data_out;

    #if VERBOSE
        printf("val_i: 0x%x\n\r", val_i);
    #endif

    float val_f = (val_i>>SIZE_FRAC)&MASK_INTEGER;
    float frac = val_i&MASK_FRAC;

    int frac_shift = (1<<SIZE_FRAC);
    //negative, check negativity by checking the value of the MSB (so bit at position SIZE_INTEGER+SIZE_FRAC-1)
    if( (val_i & (1<<(SIZE_INTEGER+SIZE_FRAC-1) )) != 0){
        //to have negative, substract the max possible value for the int part
        val_f -= (1<<SIZE_INTEGER);
    }

    frac /=frac_shift;
    val_f += frac;

    #if VERBOSE
        printf("val_f: %f\n\r", val_f);
    #endif


    tb->clk = 0;
    tb->eval();
    tb->clk = 1;
    tb->next_data_rd = 1;
    tb->eval();
    tb->next_data_rd = 0;

    return val_f;
}

void start(Vfft *tb)
{
    tb->clk = 0;
    tb->eval();
    tb->clk = 1;
    tb->start = 1;
    tb->eval();
    tb->start = 0;
}

//just simulate clock cycles
bool is_busy(Vfft *tb)
{
    tb->clk = 0;
    tb->eval();
    tb->clk = 1;
    tb->eval();
    return (tb->busy != 0);
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);

    Vfft *tb = new Vfft;

    printf("==== input ====\n\r");

    //quick test for 8 vals
    // write_val(tb, 1.0);
    // write_val(tb, 0.7071);
    // write_val(tb, 0.0);
    // write_val(tb, -0.7071);
    // write_val(tb, -1.0);
    // write_val(tb, -0.7071);
    // write_val(tb, 0.0);
    // write_val(tb, 0.7071);

    for (size_t i = 0; i < FFT_ELEMENTS; i++) {
        #if VERBOSE
            printf("%i: ", i);
        #endif
        float v_input = 0.5*sin( (2*3.1415*i)/FFT_ELEMENTS) + 0.5*cos( (2*3.1415*i*4)/FFT_ELEMENTS);
        write_val(tb, v_input);
        printf("%f, ", v_input);
    }

    start(tb);

    int count_cycles = 0;
    //wait until finshed
    while(is_busy(tb))
    {
        count_cycles++;
    }

    printf("\n\rfinished, took %i cycles\n\r", count_cycles);
    printf("==== REAL ====\n\r");

    for (size_t i = 0; i < FFT_ELEMENTS; i++) {
        #if VERBOSE
            printf("==== %d ====\n\r", i);
        #endif
        float v = get_val(tb);

        printf("%f, ", v);
    }

    printf("\n\r==== IMAG ====\n\r");

    for (size_t i = 0; i < FFT_ELEMENTS; i++) {
        #if VERBOSE
            printf("==== %d ====\n\r", i);
        #endif
        float v = get_val(tb);

        printf("%f, ", v);
    }

    printf("\n\r");

    exit(EXIT_SUCCESS);
}
