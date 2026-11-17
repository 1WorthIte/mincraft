onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {Inputs}
add wave -noupdate -label CLOCK_50 /testbench/CLOCK_50
add wave -noupdate -label KEY -radix binary /testbench/KEY
add wave -noupdate -label PS2_CLK /testbench/PS2_CLK
add wave -noupdate -label PS2_DAT /testbench/PS2_DAT

add wave -noupdate -divider {PS/2 decode (vga_demo)}
add wave -noupdate -label ps2_rec /testbench/DUT/ps2_rec
add wave -noupdate -label received_byte -radix hexadecimal /testbench/DUT/received_byte
add wave -noupdate -label left_down /testbench/DUT/left_down
add wave -noupdate -label right_down /testbench/DUT/right_down
add wave -noupdate -label jump_down /testbench/DUT/jump_down
add wave -noupdate -label hit_down /testbench/DUT/hit_down
add wave -noupdate -label wanted_code -radix hexadecimal /testbench/DUT/wanted_code
add wave -noupdate -label request_update /testbench/DUT/request_update

add wave -noupdate -divider {Command FSM (vga_demo) 0=A 1=B 2=C 3=D}
add wave -noupdate -label state -radix unsigned /testbench/DUT/y_Q
add wave -noupdate -label Esc /testbench/DUT/Esc
add wave -noupdate -label step /testbench/DUT/step
add wave -noupdate -label scancode -radix hexadecimal /testbench/DUT/scancode
add wave -noupdate -label key_up /testbench/DUT/key_up

add wave -noupdate -divider {world FSM 0=A .. 5=F}
add wave -noupdate -label state -radix unsigned /testbench/DUT/W/y_Q
add wave -noupdate -label TC -radix unsigned /testbench/DUT/W/TC
add wave -noupdate -label TR -radix unsigned /testbench/DUT/W/TR
add wave -noupdate -label block -radix unsigned /testbench/DUT/W/block
add wave -noupdate -label world_done /testbench/DUT/world_done

add wave -noupdate -divider {steve FSM 0=A .. 6=G}
add wave -noupdate -label state -radix unsigned /testbench/DUT/S/y_Q
add wave -noupdate -label S_done /testbench/DUT/S_done
add wave -noupdate -label pend /testbench/DUT/S/pend
add wave -noupdate -label phys /testbench/DUT/S/phys
add wave -noupdate -label update /testbench/DUT/S/update

add wave -noupdate -divider {steve position and pose}
add wave -noupdate -label X -radix unsigned /testbench/DUT/S/X
add wave -noupdate -label Y -radix unsigned /testbench/DUT/S/Y
add wave -noupdate -label {X (graph)} -format Analog-Step -height 60 -max 400 -min 250 -radix unsigned /testbench/DUT/S/X
add wave -noupdate -label {Y (graph)} -format Analog-Step -height 60 -max 240 -min 170 -radix unsigned /testbench/DUT/S/Y
add wave -noupdate -label {pose 0=FRONT 2/3=WALK 4=HIT} -radix unsigned /testbench/DUT/S/pose
add wave -noupdate -label face_left /testbench/DUT/S/face_left
add wave -noupdate -label rise -radix unsigned /testbench/DUT/S/rise
add wave -noupdate -label hang -radix unsigned /testbench/DUT/S/hang

add wave -noupdate -divider {steve collision}
add wave -noupdate -label side_blocked /testbench/DUT/S/side_blocked
add wave -noupdate -label on_ground /testbench/DUT/S/on_ground
add wave -noupdate -label head_blocked /testbench/DUT/S/head_blocked
add wave -noupdate -label airborne /testbench/DUT/S/airborne

add wave -noupdate -divider {Pixels sent to the VGA adapter}
add wave -noupdate -label MUX_x -radix unsigned /testbench/DUT/MUX_x
add wave -noupdate -label MUX_y -radix unsigned /testbench/DUT/MUX_y
add wave -noupdate -label MUX_color -radix hexadecimal /testbench/DUT/MUX_color
add wave -noupdate -label MUX_write /testbench/DUT/MUX_write

TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 220
configure wave -valuecolwidth 80
configure wave -signalnamewidth 1
configure wave -timelineunits us
update
WaveRestoreZoom {0 ns} {10000000 ns}
