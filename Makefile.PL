use ExtUtils::MakeMaker;
WriteMakefile(
              NAME => "LWPng-alpha",
              VERSION => '0.01',
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'}
             );
