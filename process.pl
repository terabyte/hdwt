#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Cmyers::Weight;
use Getopt::Long;
use Date::Parse;

MAIN {

    my $newVal;

    my $status = GetOptions(
        'weight=s' => \$newVal,
    );
    my $weight = Cmyers::Weight->new({
        'dbFile' => '/home/cmyers/gitrepos/weight/weight.db',
        'outputFile' => '/home/cmyers/gitrepos/weight/weight.png',
        'printData' => 1,
        'startDate' => undef, #str2time('05-05-2008'),
        'endDate' => undef,
    });

    $weight->readDB();

    if ($newVal) {
        my $time = time();
        print "Adding new point ($time, $newVal)\n";
        $weight->addDataPoint($time, $newVal);
    }

    $weight->writeDB();

    $weight->graph();

    # print 2nd graph
    $weight->{'startDate'} = str2time('05-05-2010');
    $weight->{'outputFile'} = '/home/cmyers/gitrepos/weight/weight-all.png';
    $weight->graph();

    exit 0;
};
