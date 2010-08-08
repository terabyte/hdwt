
# Plot weightloss
# Used info from
# http://ixpressor.wordpress.com/2010/01/25/plotting-loss-of-weight-with-gnuplot/
# 
set term postscript enh "Helvetica" 24
set terminal png rounded size 1024, 768
set output "weight.png"

set title "Weight over time for terabyte"
set grid

set xlabel "Date"
set xdata time
set timefmt "%s"

set ylabel "Weight in lbs"
#set ytics nomirror 5
#set xtics 
#set mytics 1

plot "weight.dat" using 1:2 title "Measured weight" with linespoints lt rgb '#000033' pt 5
#plot "weight.dat" using 1:2 

#set borde -1 lw 3
#
#set size ratio 0.5
#set title "Weight"
#
#set xlabel "Date"
#set ylabel "Weight"
#
#plot 
