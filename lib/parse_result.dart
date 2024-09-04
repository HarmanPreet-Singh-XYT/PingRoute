Map<String, dynamic> parseStringToMap(String input) {
  // Remove curly braces
  input = input.substring(1, input.length - 1);

  // Split into key-value pairs
  List<String> keyValuePairs = input.split(',');

  // Initialize an empty map to store the parsed values
  Map<String, dynamic> resultMap = {};

  // Iterate through each key-value pair
  for (String pair in keyValuePairs) {
    // Split each pair into key and value
    List<String> keyValue = pair.split(':');

    // Get the key and value, trimming any excess whitespace
    String key = keyValue[0].trim();
    String value = keyValue[1].trim();

    // Convert the value to the appropriate type
    dynamic parsedValue;
    if (key == 'hop' || key == 'ping') {
      parsedValue = int.parse(value);
    } else {
      parsedValue = value;
    }

    // Add the key-value pair to the result map
    resultMap[key] = parsedValue;
  }

  return resultMap;
}
List<Map<String, dynamic>> parseArrayOfStrings(List<String> inputList) {
  // Initialize an empty list to store the parsed maps
  List<Map<String, dynamic>> resultList = [];

  // Iterate through each string in the input list
  for (String item in inputList) {
    // Parse the string into a map
    Map<String, dynamic> parsedMap = parseStringToMap(item);
    // Add the parsed map to the result list
    resultList.add(parsedMap);
  }

  return resultList;
}