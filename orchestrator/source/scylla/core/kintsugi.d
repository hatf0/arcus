module scylla.core.kintsugi;
import std.stdio;
import scylla.core.server;
import scylla.core.firecracker;
import bap.models.vps;
import std.file;
import std.concurrency;
import std.process;
import std.algorithm.searching;
import core.exception;
import std.string;
import scylla.core.resource_manager;
import scylla.zone.zone;
import scylla.nic.nic;

class Kintsugi {
    private {
	string[string] vms;
    }


    this() 
    {

    }
}
