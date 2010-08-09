#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Cmyers::Weight;

MAIN {
    my $weight = Cmyers::Weight->new({
        'dbFile' => '/home/cmyers/gitrepos/weight/weight.db',
    });

    #$weight->readSimpleFile('/home/cmyers/gitrepos/weight/weight.dat');

    #$weight->writeDB();
    $weight->readDB();

    open(my $FH, '<', '/home/cmyers/gitrepos/weight/fromabout.dat') or die;
    while (my $line = <$FH>) {
        if ( $line =~ m/([^ ]+) (.*)/ ) {
            my ($date, $val) = ($1, $2);
            print "Found weight $val on date $date\n";
            $weight->addDataPoint($date, $val);
        }
    }

    # read in new data
    $weight->recalculateAll();

    $weight->writeDB();

    $weight->graph("weight.png");

    exit 0;
};
