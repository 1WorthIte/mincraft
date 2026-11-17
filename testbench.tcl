# ModelSim script for Mincraft (milestone 1)
# This folder (ModelSim/) goes inside the project folder, next to vga_demo.v, object_mem.v and MIF/.
# In ModelSim: File > Change Directory... to this folder, then in the Transcript type:
#     do testbench.tcl

# stop any simulation that is currently running
quit -sim

# object_mem looks for ./MIF/*.mif relative to where ModelSim runs, so copy the MIF folder here
file delete -force MIF
file copy -force ../MIF MIF

# create the default "work" library
vlib work

# compile the design (object_mem.v first, because vga_demo.v sets `default_nettype none)
# -timescale gives the design files the same 1 ns time unit as the testbench
vlog -timescale 1ns/1ns ../object_mem.v ../vga_demo.v

# compile the testbench (also holds the simulation-only vga_adapter stand-in)
vlog -timescale 1ns/1ns testbench.v

# start the simulator with the Intel libraries that altsyncram (object_mem) needs
vsim work.testbench -Lf 220model -Lf altera_mf_ver -Lf verilog

# show the waveforms listed in wave.do
do wave.do

# run until the testbench calls $stop (about 9 ms of simulated time)
run -all
