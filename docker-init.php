#!/usr/bin/env php
<?php
require_once '../htdocs/master.inc.php';
require_once DOL_DOCUMENT_ROOT.'/core/lib/admin.lib.php';

printf("Activating module User... ");
activateModule('modUser');
printf("OK\n");
