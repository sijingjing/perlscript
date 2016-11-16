#!/usr/bin/env perl
use Spreadsheet::ParseExcel;
use Data::Dumper;
use strict;
use warnings;
use utf8;
use utf8::all;
use Add;
use 5.010;
use YAML::XS;

my ($file, $prefix) = @ARGV;
$prefix = '86'.$prefix;
my $parser   = Spreadsheet::ParseExcel->new();
my $workbook = $parser->parse($file);

if ( !defined $workbook ) {
    die $parser->error(), ".\n";
}


my %all_addrs = Add->load_all_adds;

my %phonenumber_geo;
my %prefix_num;
for my $worksheet ( $workbook->worksheets() ) {
    my ( $row_min, $row_max ) = $worksheet->row_range();
    my ( $col_min, $col_max ) = $worksheet->col_range();

    for my $col ( 3 .. $col_max ) {
        my $cell = $worksheet->get_cell( 2, $col );
        next unless $cell;
        $prefix_num{$col} = $cell->value;
    }

    for my $row ( 3 .. $row_max ) {
        my $province = $worksheet->get_cell($row, 0)->value;
        my $city     = $worksheet->get_cell($row, 1)->value;
        for my $col ( 3 .. $col_max ) {
            my $cell = $worksheet->get_cell( $row, $col );
            next unless $cell;

            my $value = $cell->value();
            # $value =~ s/(\d+)-(\d+)(?{$temp = join '、', ($1 .. $2)})/$temp/g;
            while ($value =~ m/(\d+)-(\d+)/) {
                my $temp;
                my @temp_array = ($1 .. $2);
                my @num_array;
                while (scalar @temp_array) {
                    my $shift_temp = shift @temp_array;
                    if ($shift_temp % 10 == 0 && $shift_temp + 9 <= $temp_array[-1]) {
                        my $push_num = $shift_temp;
                        chop $push_num;
                        push @num_array, $push_num;
                        @temp_array = grep { $_ > $shift_temp + 9 } @temp_array;
                    } else {
                        push @num_array, $shift_temp;
                    }
                }
                $temp = join ',', @num_array;
                $value =~ s/(\d+)-(\d+)/$temp/;
            }
            my @nums = split '[^\d]', $value;
            @nums = map ("86".$prefix_num{$col}.$_,  @nums);
            for my $num (@nums) {
                # my $new_add = Add->new('prov' => $province, 'city' => $city);
                my $new_add = $all_addrs{$province.'-'.$city};
                my @adds;
                if ($phonenumber_geo{$num}) {
                    my $addr = $phonenumber_geo{$num};
                    if ($addr) {
                        for my $add (@$addr) {
                            die "address error: $num $province - $add->{'prov'}" unless ($add->{'prov'} =~ /$province/);
                        }
                    }
                    push @adds, @$addr;
                }
                push @adds, $new_add;
                $phonenumber_geo{$num} = \@adds;
            }
        }
    }
}
# print Dumper %phonenumber_geo;

sub get_en_add {
    my $adds = shift;
    my $add_str;
    if (scalar @$adds == 1) {
        $add_str = $adds->[0]->get_addr_en;
    } elsif (scalar @$adds > 1) {
        my @temp_adds = @$adds;
        $add_str = $adds->[0]->get_addr_en;
        shift @temp_adds;
        for (@temp_adds) {
            $add_str = $_->get_city_en ."/".$add_str;
        }
    } else {
        $add_str = "===================";
    }
    $add_str;
}

sub get_zh_add {
    my ($adds) = shift;
    #    print Dumper $add;
    my $add_str;
    if (scalar @$adds == 1) {
        $add_str = $adds->[0]->get_addr_zh;
    } elsif (scalar @$adds > 1) {
        my @temp_adds = @$adds;
        $add_str = $temp_adds[0]->get_addr_zh;
        shift @temp_adds;
        for (@temp_adds) {
            $add_str .= "\x{3001}".$_->get_city_cn;
        }
    } else {
        $add_str = "=============";
    }
    $add_str;
}



sub get_origin_data_cn {
    if (-f $prefix.'_zh.txt') {
        open FH, "<", $prefix.'_zh.txt' or die "open err";
    } else {
        open FH, "<", "86zh.txt" or die "open err";
    }
    my @google_data;
    while (<FH>) {
        chomp;
        next if /^#/;
        next if /^\s*$/;
        push @google_data, $_;
    }
    say "read ok";
    close FH;
    @google_data;
}

sub get_google_data_en {
    if (-f $prefix.'_en.txt') {
        open FH, "<", $prefix.'_en.txt' or die "open err";
    } else {
        open FH, "<", "86en.txt" or die "open err";
    }
    my @google_data_en;
    while (<FH>) {
        chomp;
        next if /^#/;
        next if /^\s*$/;
        push @google_data_en, $_;
    }
    close FH;
    @google_data_en;
}

my @remove;
my @google_data = get_origin_data_cn;
@google_data = grep { $_ =~ /^(\d{5})/ && $1 == $prefix } @google_data;
my %google_geo = map {$_ =~ /^(\d+)|(.*)$/; $1 => $2 } @google_data;

foreach my $number (keys %phonenumber_geo) {
    my $match = 0;
    push @remove, $number and next if ($google_geo{$number});
    my ($key) = grep { $number =~ /^$_\d+$/ } keys %google_geo;
    push @remove, $key and next if ($key);
}

&write_out_zh;
say "zh write OK!";
&write_out_en;
say "en write OK!";

sub write_out_en {
    my @google_data_en = get_google_data_en;
    @google_data_en = grep { $_ =~ /^(\d{5})/ && $1 == $prefix } @google_data_en;
    my %google_geo_en = map {$_ =~ /^(\d+)|(.*)$/; $1 => $2 } @google_data_en;

    open EN, ">", $prefix."_en.txt" or die "open err";
    delete $google_geo_en{$_} for @remove;
    for my $number (keys %phonenumber_geo) {
        my $add = $phonenumber_geo{$number};
        my $en_add = get_en_add($add);
        $google_geo_en{$number} = $en_add;
    }
    say EN $_.'|'.$google_geo_en{$_} for (sort keys %google_geo_en);
    close EN;
}

sub write_out_zh {
    open ZH, ">", $prefix."_zh.txt"  or die "open err";
    delete $google_geo{$_} for @remove;
    for my $number (keys %phonenumber_geo) {
        my $add = $phonenumber_geo{$number};
        #   print Dumper $add;
        #   print Dumper $phonenumber_geo{number};
        my $zh_add = get_zh_add($add);
        $google_geo{$number} = $zh_add;
    }
    for (sort keys %google_geo) {
        say ZH $_.'|'.$google_geo{$_};
    }
    close ZH;
}


#close OUT;
