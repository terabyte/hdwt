#!/usr/bin/perl

use strict;
use warnings;

use Date::Parse;

MAIN {

    my $infile = "weight.dat";
    my $outfile = "graph.dat";

    # in format: 
    # 310.2 Sat Jun 30 11:12:44 PDT 2007
    #
    # outformat:
    # (epoc) (weight) (trend)
    # 123456 320.2 322.1945


    open(my $FH, '<', $infile) or die "Unable to open $infile: $!\n";

    my $data = [];
    while (my $line = <$FH>) {

        my ($weight, $date);
        if ($line =~ m/([^ ]+) (.*)/) {
            ($weight, $date) = ($1, $2);

            my $time = str2time($date);

            print "Date: $time $weight\n";

            push @{$data}, [$time, $weight];

            next;
        }

        warn "Unable to parse line: $line\n";
    }

    # process Moving Average
    # Reference:  used here, but figured it out myself
    # http://en.wikipedia.org/wiki/Moving_average#Exponential_moving_average

    my $startDate = $data->[0]->[0];
    for (my $n = 0; $n < scalar @{$data}; ++$n) {
        my $point = $data->[$n];
        my ($date, $weight) = @{$point};

        my $halflife = 7*24*60*60; # 7 days in seconds
        my $dateDelta = $date - $startDate;
        print "Date Delta = $dateDelta\n";
        my $expWeight = getDecayForDate($startDate, $date, $halflife);
        print "weight = $expWeight\n";

        my $EMA = 0;
        for (my $i = 0; $i < $n; ++$i) {
            # calculate EMA from 0 to N
            # part = expWeight * weight
            # part = 1/($n) * decay * weight
            my $part = 1.0/$n * getDecayForDate($startDate, $date, $halflife) * $weight;
            print "Part for ($date, $weight) = $part\n";
            $EMA += $part;
        }
        print "Total EMA: $EMA\n";
    }
    exit 0;

    close($FH) or die "Unable to close $infile: $!\n";

    open(my $OFH, '>', $outfile) or die "Unable to open file $outfile: $!\n";
    foreach my $datum ( @{$data} ) {
        my ($date, $weight) = @{$datum};
        print $OFH "$date $weight\n";
    }
    close($OFH) or die "Unable to close $outfile: $!\n";
    exit 0;
};

# Weight at time differential t = initialWeight * e^(Q*t)
# Q = decay constant = -ln(2) / t(1/2)
# t(1/2) = half life
sub getDecayForDate {
    my ($startDate, $currentDate, $halflife) = @_;

    my $q = log(2.0)/$halflife;
    return ( 1.0 * exp(-1.0 * $q * ($currentDate - $startDate)) );
}


#sub calculateEMA {
#    my ($data, $n) = shift;
#
#    my $EMA = [ undef, $data->[0]->[1] ];
#    my $i = 2;
#    while ( $i <= $n ) {
#        my $curEMA = 0;
#        for (my $k = $i; $k > 0; --$k) {
#            # add in each weight, multiplied by the "weight" it has, exp.
#            # decaying
#
#
#
#    }
#
#    #return $EMA->[$n];
#}

