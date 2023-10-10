#!/bin/sh

IOE_DIR=/usr/ioe/skynet/..
SKYNET_FILE=/IamNotExits.unknown
SKYNET_PATH=skynet
FREEIOE_FILE=/tmp/freeioe.force.upgrade.tar.gz
FREEIOE_PATH=freeioe

date > $IOE_DIR/ipt/rollback
cp -f $SKYNET_PATH/cfg.json $IOE_DIR/ipt/cfg.json.bak
cp -f $SKYNET_PATH/cfg.json.md5 $IOE_DIR/ipt/cfg.json.md5.bak

cd $IOE_DIR
if [ -f $SKYNET_FILE ]
then
	cd $SKYNET_PATH
	rm ./lualib -rf
	rm ./luaclib -rf
	rm ./service -rf
	rm ./cservice -rf
	tar xzf $SKYNET_FILE

	if [ $? -eq 0 ]
	then
		echo "Skynet upgrade is done!"
	else
		echo "Skynet uncompress error!! Rollback..."
		rm -f $SKYNET_FILE
		sh $IOE_DIR/ipt/rollback.sh
		exit $?
	fi
fi

cd "$IOE_DIR"
if [ -f $FREEIOE_FILE ]
then
	cd $FREEIOE_PATH
	rm ./www -rf
	rm ./lualib -rf
	rm ./snax -rf
	rm ./test -rf
	rm ./service -rf
	rm ./ext -rf
	tar xzf $FREEIOE_FILE

	if [ $? -eq 0 ]
	then
		echo "FreeIOE upgrade is done!"
	else
		echo "FreeIOE uncompress error!! Rollback..."
		rm -f $FREEIOE_FILE
		sh $IOE_DIR/ipt/rollback.sh
		exit $?
	fi
fi

if [ -f $IOE_DIR/ipt/strip_mode ]
then
	rm -f $IOE_DIR/ipt/rollback
	rm -f $IOE_DIR/ipt/upgrade_no_ack

	if [ -f $IOE_DIR/ipt/rollback.sh.new ]
	then
		mv -f $IOE_DIR/ipt/rollback.sh.new $IOE_DIR/ipt/rollback.sh
	fi

	[ -f $SKYNET_FILE ] && rm -f $SKYNET_FILE
	[ -f $FREEIOE_FILE ] && rm -f $FREEIOE_FILE

	exit 0
fi

rm -f $IOE_DIR/ipt/rollback
rm -f $IOE_DIR/ipt/upgrade_no_ack

if [ -f $IOE_DIR/ipt/rollback.sh.new ]
then
	mv -f $IOE_DIR/ipt/rollback.sh.new $IOE_DIR/ipt/rollback.sh
fi

if [ -f $SKYNET_FILE ]
then
	mv -f $SKYNET_FILE $IOE_DIR/ipt/skynet.tar.gz
fi
if [ -f $FREEIOE_FILE ]
then
	mv -f $FREEIOE_FILE $IOE_DIR/ipt/freeioe.tar.gz
fi

sync

