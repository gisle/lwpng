use ExtUtils::MakeMaker;
WriteMakefile(
              NAME => "LWPng-alpha",
              VERSION => '0.14',
	      PREREQ_PM => { LWP => '5.30', },
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'}
             );
