use ExtUtils::MakeMaker;
WriteMakefile(
              NAME => "LWPng-alpha",
              VERSION => '0.05',
	      PREREQ_PM => { LWP => '5.20', },
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'}
             );
