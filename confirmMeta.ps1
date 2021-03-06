﻿$script:logger

#Logging
function logging( [string]$msg ) {
    #logのメッセージ
    $log = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"
    $log = $log + " " + $msg
    #logファイル無かったら作る
    if( $null -eq $logger ) {
        $parm = Get-Date -Format "yyyyMMdd_HH.mm.ss.fff"
        $logname = "LOG" + "_" + $parm + ".log"
        $script:logger = New-Item $logname -Force
    }
    #log出力
    Write-Output $log | Out-File -FilePath $script:logger -Encoding Default -append
#    return $log
}
#指定した文字列以降を取り出すよ
function getLastStr {
    param (
        [string]$sourceStr,
        [string]$findStr
    )
    $findInx = $sourceStr.indexOf( $findStr )
    $resultStr = $sourceStr.Substring( $findInx + $findStr.Length )
    return $resultStr
}
#ファイル処理する関数だよ
function doCopy( $1 ) {
    #dupがついてない元ファイルを作成するよ
    $sourceFile = $1.FullName.Substring( 0, $1.FullName.Length - 4 )
    #dupが無いファイルがあるか確認するよ
    if( Test-Path $sourceFile ) {
        #ファイルコピー
        Copy-Item $1.FullName $sourceFile
        #loggingする
        $msg = "COPY : " + $1.FullName + " TO " + $sourceFile
        logging -msg $msg
    }
}
#フォルダ指定するダイアログ表示
function Select-Folder(
    [string]$Path = ".",
    [string]$Description,
    [switch]$ShowNewFolder)
{
    Add-Type -assemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = (Get-Item $PWD).FullName
    $dialog.Description = $Description
    #[新しいフォルダ]ボタンを表示するか？
    $dialog.ShowNewFolderButton = $ShowNewFolder
    # ダイアログを表示
    if($dialog.ShowDialog() -eq "OK")
    {
      #入力されたファイル名を返す
      return $dialog.SelectedPath
    }
}
#Meta側で削除されたファイルを探し出す
function findDelete( $cloneFile, $clonePath, $metaPath ) {
    #force-appまでで変換しとく
    $lastStr = getLastStr $cloneFile.FullName "force-app"
    #Clone側のファイル名を取り出してMeta側のパスにくっつけて、存在をみる
    $metaFileName = Join-Path $metaPath $lastStr
    #Meta側にファイルがなければ画面とログに出力
    if( !(Test-Path $metaFileName) ) {
        $msg = "WARNING!!! [" + $cloneFile.FullName + "] is not exsits!!"
        Write-Host $msg -ForegroundColor Red
        logging -msg $msg
    }
}

#logging start
logging -msg "Start!"
#DevHubに接続してSFDXプロジェクトに変換するまでやってみる、ほんとはDevHubから処理したいけどBATファイルなので無理。。。BATの中解析したけど無理。。。
#package.xmlが存在することを確認する
if( !(Test-Path "./package.xml") ) {
    $msg = "FATAL!!! package.xml is not Exsits!!"
    Write-Host $msg -ForegroundColor Red
    logging -msg $msg
    Exit-PSHostProcess
}
#sfdx-project.jsonが存在することを確認する
if( !(Test-Path "./sfdx-project.json") ) {
    $msg = "FATAL!!! sfdx-project.json is not Exsits!!"
    Write-Host $msg -ForegroundColor Red
    logging -msg $msg
    Exit-PSHostProcess
}
#configディレクトリが存在することを確認する
if( !(Test-Path "./config") ) {
    $msg = "FATAL!!! config Directry is not Exsits!!"
    Write-Host $msg -ForegroundColor Red
    logging -msg $msg
    Exit-PSHostProcess
}
#メタデータを取得する、BATファイルなので返り値みれず。。。ほんとは処理したい
Start-Process sfdx -ArgumentList "force:mdapi:retrieve -s -r ./mdapipkg -k ./package.xml -u DevHub" -Wait
#解凍する
Expand-Archive -Path "./mdapipkg/unpackaged.zip" -DestinationPath "./mdapipkg" -Force
#プロジェクトに変換する
Start-Process sfdx -ArgumentList "force:mdapi:convert -r ./mdapipkg" -Wait
#force-appディレクトリが存在することを確認する
if( !(Test-Path "./force-app") ) {
    $msg = "FATAL!!! convert is not Success!!"
    Write-Host $msg -ForegroundColor Red
    logging -msg $msg
    Exit-PSHostProcess
}
#コンバートした結果のディレクトリを格納
$metapath = (Convert-Path "./force-app")

#ダイアログ表示
$clonepath = Select-Folder -$Description "クローンしたforce-appディレクトリを指定してください。"
#$metapath = Select-Folder -$Description "メタデータのforce-appディレクトリを指定してください。"
#NULLチェック、ディレクトリ指定してるかどうか
if( $null -eq $clonepath ) {
    Write-Host "クローンのパスを指定してください。" -ForegroundColor Red
    logging -msg "EXCEPTION! NOT CLONE PATH"
    exit
}
logging -msg "Copy Dup!!"
#まずdupファイルがあればdup無しにコピーする
$files = Get-ChildItem -Path $metapath -Recurse -Filter *.dup -File
#取り出したdupを回す。
$files | ForEach-Object -Process {doCopy $_}

#削除されちゃったファイルを探す
logging -msg "Find DeletedFile!!"
$files = Get-ChildItem -Path $clonepath -Recurse -File
$files | ForEach-Object -Process {findDelete $_ $clonepath $metaPath }
#コピーを実行するか決める
#■変数格納箇所
$CHESEN = "コピーを実行しますか。"
$CHETIT = "最終確認"
$CHEKIN = "OKCancel"
$CHEICO = "None"
$CHEBUT = "button1"
Add-Type -Assembly System.Windows.Forms
$result = [System.Windows.Forms.MessageBox]::Show("$CHESEN","$CHETIT","$CHEKIN","$CHEICO","$CHEBUT")
#メッセージボックスのハンドリング
if( 'OK' -eq $result ){
    Write-Output "コピーを開始します。"
    #metaをcloneにコピー
    $dest = Split-Path $clonepath -Parent
    Copy-Item $metapath -Destination $dest -Recurse -Exclude "*.dup" -Force
    logging -msg "Copy complete!"
} else {
    [System.Windows.Forms.MessageBox]::show("コピーを中止しました。","最終確認","OK","None","button1")
    Write-Output "コピーを中止しました。"
    logging -msg "Copy abort!"
}
Write-Output "処理終了"
logging -msg "Completed!!"
