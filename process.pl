#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Cmyers::Weight;

MAIN {
    my $weight = Cmyers::Weight->new({
        'dbFile' => '/home/cmyers/gitrepos/weight/weight.db',
        'printData' => 1,
    });

    $weight->readDB();

    my $val = '316.2';
    $weight->addDataPoint(time(), $val);

    $weight->writeDB();
    $weight->graph("weight.png");

    exit 0;
};
