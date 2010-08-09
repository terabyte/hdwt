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

    # change hl
    $weight->{'halfLife'} = 7*24*60*60;
    $weight->recalculateAll();

    $weight->writeDB();
    $weight->graph("weight.png");

    exit 0;
};
