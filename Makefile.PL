use ExtUtils::MakeMaker;
WriteMakefile(
              NAME => "LWPng-alpha",
              VERSION => '0.03',
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'}
             );
