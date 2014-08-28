use strict;

while(<STDIN>){
    s/\r//;
    s/\n//;

    # get read group name
    my $rg = $1 if (/.+(RG:Z:.+?)(\s.*|\Z)/); 

    my @F = split /\t/, $_, -1;

    # skip the rows that both ends of a pair match to the same location,
    # because both should have been captured already in the first slice
    next if ($F[6] eq "=" && $F[3] == $F[7]);

    my $chr = $F[6] eq "=" ? $F[2] : $F[6];

    #print "$chr\t$F[7]\t" . ($F[7] + 1) . "\t$F[0]~$rg\n";
    print "$chr\t" . ($F[7] - 1) . "\t$F[7]\t$F[0]~$rg~$F[1]\n";

}
