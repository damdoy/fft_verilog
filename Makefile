all:
	verilator -Wall --cc fft.v --exe main.cpp
	make -j -C obj_dir -f Vfft.mk Vfft
