# Indluxdb retention manager

## Problem

If you are collecting a lot of data, you can't keep your influxdb data indefinitely.

Retrieving a lot of data over huge period of time will slow down your queries.

Enter continuous queries, they run every few minutes and write your data with lower precision.

However, continuous queries are pain to setup if you have many measurements and databases.

## Solution

Influxdb retention manager is operating through two simple steps:

1. It will scan database and prepare yaml file for you with all functions which allow you to customise them.
2. It will setup your new retention policies and continuous questies which will fill up this new data.


# Remaining problems and TODOs

It's not enough to only create retention policies and continuous queries, you actually need to have graph web interface which will support those retention policies and invoke them automatically based on time range selected.

Relevant issues:
* https://github.com/grafana/grafana/issues/4262
* possible solution within influx itself? https://github.com/influxdata/influxdb/issues/2625

# Usage

## Run recon

```
$ ruby irm.rb recon --database my_db
```

For full list of options, use:

```
ruby irm.rb help recon
```

## Adjust retention policies if necessary:

Now you can edit yaml file which will be produced by ```recon``` command

## Create continuous queries

```ruby irm.rb create_cq --database my_db```