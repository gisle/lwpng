use ExtUtils::MakeMaker;
WriteMakefile(
              NAME => "LWPng-alpha",
              VERSION => '0.02',
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'}
             );
