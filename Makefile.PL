use ExtUtils::MakeMaker;
WriteMakefile(
              NAME => "LWP-ng",
              VERSION => '0.01',
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'}
             );
