import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class Graph extends StatefulWidget {
  const Graph({super.key, required this.dataType, required this.data,required this.interval,required this.isRunning});

  final String dataType;
  final Map<String, dynamic> data;
  final int interval;
  final bool isRunning;

  @override
  State<Graph> createState() => _GraphState();
}

class _GraphState extends State<Graph> {
  List<Color> gradientColors = [
    Colors.cyan,
    Colors.blue,
  ];

  double maxLatency = 5;
  double maxAvgLatency = 5;
  double maxJitter = 5;

  bool showAvg = false;
  final limitCount = 11;
  //points for packet loss
  final dataPointsPL = <FlSpot>[];
  final dataPointTimePL = <String>[];
  final dataPointsLatency = <FlSpot>[];
  final dataPointTimeLatency = <String>[];
  final dataPointsAvgLatency = <FlSpot>[];
  final dataPointTimeAvgLatency = <String>[];
  final dataPointsJitter = <FlSpot>[];
  final dataPointTimeJitter = <String>[];
  double xValue = 0;
  double xLatency = 0;
  double xAvgLatency = 0;
  double xJitter = 0;

  late Timer timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(Duration(milliseconds: widget.interval), (timer) {
      setState(() {
        if(widget.isRunning){
          //check data
          double yValue = widget.data['pl'].length > 0
            ? double.parse('${widget.data['pl'].last['value']}')
            : 0;
          double yLatency = widget.data['pings'].length > 0
            ? double.parse('${widget.data['pings'].last['value']}')
            : 0;
          double yAvgLatency = widget.data['avg'].length > 0
            ? double.parse('${widget.data['avg'].last['value']}')
            : 0;
          double yJitter = widget.data['jitter'].length > 0
            ? double.parse('${widget.data['jitter'].last['value']}')
            : 0;

          // set max values
          if(yLatency > maxLatency) maxLatency=yLatency+20;
          if(yAvgLatency > maxAvgLatency) maxAvgLatency=yAvgLatency+20;
          if(yJitter > maxJitter) maxJitter=yJitter+20;

          // remove first element (remove oldest points)
          if (dataPointsPL.length >= limitCount) {
            dataPointsPL.removeAt(0);
          }
          if (dataPointsLatency.length >= limitCount) {
            dataPointsLatency.removeAt(0);
          }
          if (dataPointsAvgLatency.length >= limitCount) {
            dataPointsAvgLatency.removeAt(0);
          }
          if (dataPointsJitter.length >= limitCount) {
            dataPointsJitter.removeAt(0);
          }

          // add new points
          dataPointsPL.add(FlSpot(xValue, yValue));
          dataPointTimePL.add('${widget.data['pl'].last['time']}');
          dataPointsLatency.add(FlSpot(xLatency, yLatency));
          dataPointTimeLatency.add('${widget.data['pings'].last['time']}');
          dataPointsAvgLatency.add(FlSpot(xAvgLatency, yAvgLatency));
          dataPointTimeAvgLatency.add('${widget.data['avg'].last['time']}');
          dataPointsJitter.add(FlSpot(xJitter, yJitter));
          dataPointTimeJitter.add('${widget.data['jitter'].last['time']}');
          
          //increment for next points
          xValue += 1;
          xLatency += 1;
          xAvgLatency += 1;
          xJitter +=1;
        }else{
          timer.cancel();
        }
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        AspectRatio(
          aspectRatio: 1.70,
          child: Padding(
            padding: const EdgeInsets.only(
              right: 18,
              left: 12,
              top: 24,
              bottom: 12,
            ),
            child: LineChart(
              widget.dataType=='pl' ? packetLoss() : widget.dataType=='jt' ? jitterChart() : widget.dataType=='lt' ? latencyChart() : avgLatencyChart(),
              duration:Duration.zero
            ),
            
          ),
        ),
      ],
    );
  }

  //----------------------------------------------------------------------------------------------Packet Loss------------------------------------------------------------

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 10,
      color: Colors.white,
    );

    int index = value.toInt();
    String text ='';
    if (index >= 0 && index < dataPointTimePL.length) {
      text = dataPointTimePL[index]; // Use the timestamp at the corresponding index
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.white,
    );

    if (value % 10 == 0 && value >= 0 && value <= 100) {
      return Text('${value.toInt()}%', style: style, textAlign: TextAlign.left);
    } else {
      return Container();
    }
  }

  LineChartData packetLoss() {
    double maxX = dataPointsPL.isNotEmpty ? dataPointsPL.last.x : 0;
    double minX = maxX - (limitCount - 1).toDouble();

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 10,
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: bottomTitleWidgets,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 20,
            getTitlesWidget: leftTitleWidgets,
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d)),
      ),
      minX: minX,
      maxX: maxX,
      minY: 0,
      maxY: 100,
      lineBarsData: [
        LineChartBarData(
          show: dataPointsPL.isNotEmpty,
          spots: dataPointsPL,
          isCurved: true,
          gradient: LinearGradient(
            colors: gradientColors,
          ),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: const FlDotData(
            show: false,
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors
                  .map((color) => color.withOpacity(0.3))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }



  //--------------------------------------------------------------------------------------------Latency------------------------------------------------------------------------------------------------------

  Widget bottomTitleWidgetsLatency(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 10,
      color: Colors.white,
    );

    int index = value.toInt();
    String text = '';
    if (index >= 0 && index < dataPointTimeLatency.length) {
      text = dataPointTimeLatency[index]; // Use the timestamp at the corresponding index
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  Widget leftTitleWidgetsLatency(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.white,
    );

     if (value >= 0 && value <= maxLatency) {
      return Text('${value.toInt()}ms', style: style, textAlign: TextAlign.left);
    } else {
      return Container();
    }
  }

  LineChartData latencyChart() {
    double maxX = dataPointsLatency.isNotEmpty ? dataPointsLatency.last.x : 0;
    double minX = maxX - (limitCount - 1).toDouble();
    // double maxY = dataPointsLatency.isNotEmpty
    //     ? dataPointsLatency.map((e) => e.y).reduce((a, b) => a > b ? a : b)
    //     : 100; // Adjust based on expected maximum latency

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: maxLatency/10, // Adjust based on expected latency range
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: bottomTitleWidgetsLatency,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: maxLatency/5, // Adjust based on expected latency range
            getTitlesWidget: leftTitleWidgetsLatency,
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d)),
      ),
      minX: minX,
      maxX: maxX,
      minY: 0,
      maxY: maxLatency,
      lineBarsData: [
        LineChartBarData(
          show: dataPointsLatency.isNotEmpty,
          spots: dataPointsLatency,
          isCurved: true,
          gradient: LinearGradient(
            colors: gradientColors,
          ),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: const FlDotData(
            show: false,
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors
                  .map((color) => color.withOpacity(0.3))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  //-----------------------------------------------------------------------------Jitter-----------------------------------------------------------------------------------
  Widget bottomTitleWidgetsJitter(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 10,
      color: Colors.white,
    );

    int index = value.toInt();
    String text = '';
    if (index >= 0 && index < dataPointTimeJitter.length) {
      text = dataPointTimeJitter[index]; // Use the timestamp at the corresponding index
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  Widget leftTitleWidgetsJitter(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.white,
    );

     if (value >= 0 && value <= maxJitter) {
      return Text('${value.toInt()}ms', style: style, textAlign: TextAlign.left);
    } else {
      return Container();
    }
  }

  LineChartData jitterChart() {
    double maxX = dataPointsJitter.isNotEmpty ? dataPointsJitter.last.x : 0;
    double minX = maxX - (limitCount - 1).toDouble();

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: maxJitter/10, // Adjust based on expected latency range
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: bottomTitleWidgetsJitter,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: maxJitter/5, // Adjust based on expected latency range
            getTitlesWidget: leftTitleWidgetsJitter,
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d)),
      ),
      minX: minX,
      maxX: maxX,
      minY: 0,
      maxY: maxJitter,
      lineBarsData: [
        LineChartBarData(
          show: dataPointsJitter.isNotEmpty,
          spots: dataPointsJitter,
          isCurved: true,
          gradient: LinearGradient(
            colors: gradientColors,
          ),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: const FlDotData(
            show: false,
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors
                  .map((color) => color.withOpacity(0.3))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  //-----------------------------------------------------------------------------Average Latency----------------------------------------------------------------------------

  Widget bottomTitleWidgetsAvgLatency(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 10,
      color: Colors.white,
    );

    int index = value.toInt();
    String text = '';
    if (index >= 0 && index < dataPointTimeLatency.length) {
      text = dataPointTimeLatency[index]; // Use the timestamp at the corresponding index
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  Widget leftTitleWidgetsAvgLatency(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.white,
    );

     if (value >= 0 && value <= maxAvgLatency) {
      return Text('${value.toInt()}ms', style: style, textAlign: TextAlign.left);
    } else {
      return Container();
    }
  }

  LineChartData avgLatencyChart() {
    double maxX = dataPointsAvgLatency.isNotEmpty ? dataPointsAvgLatency.last.x : 0;
    double minX = maxX - (limitCount - 1).toDouble();
    // double maxY = dataPointsLatency.isNotEmpty
    //     ? dataPointsLatency.map((e) => e.y).reduce((a, b) => a > b ? a : b)
    //     : 100; // Adjust based on expected maximum latency

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: maxAvgLatency/10, // Adjust based on expected latency range
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return const FlLine(
            color: Colors.lightBlue,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: bottomTitleWidgetsAvgLatency,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: maxAvgLatency/5, // Adjust based on expected latency range
            getTitlesWidget: leftTitleWidgetsAvgLatency,
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d)),
      ),
      minX: minX,
      maxX: maxX,
      minY: 0,
      maxY: maxAvgLatency,
      lineBarsData: [
        LineChartBarData(
          show: dataPointsAvgLatency.isNotEmpty,
          spots: dataPointsAvgLatency,
          isCurved: true,
          gradient: LinearGradient(
            colors: gradientColors,
          ),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: const FlDotData(
            show: false,
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors
                  .map((color) => color.withOpacity(0.3))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }
}
