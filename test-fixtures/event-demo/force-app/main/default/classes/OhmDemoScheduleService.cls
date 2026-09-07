/**
 * Deterministic schedule preparation for the Ohm event fixtures.
 * New fixture code. Agent action wiring is adapted from Salesforce Agent Script Recipes.
 * No records are written, and no external service or model is invoked.
 */
public with sharing class OhmDemoScheduleService {
    public class Request {
        @InvocableVariable(label='Activities' description='One activity per line: HH:MM|duration minutes|activity name|location. Forward the supplied text unchanged.' required=true)
        public String activities;
    }
    public class Response {
        @InvocableVariable(label='Validated schedule' description='A chronological schedule with at least sixty minutes between included activities, or an input validation message.')
        public String scheduleText;
        @InvocableVariable(label='Valid input' description='True when every supplied activity passed format and range validation.')
        public Boolean valid;
    }
    private class Activity implements Comparable {
        Integer startMinute;
        Integer duration;
        Integer inputIndex;
        String name;
        String location;
        public Integer compareTo(Object other) {
            Activity activity = (Activity)other;
            if (startMinute != activity.startMinute) return startMinute < activity.startMinute ? -1 : 1;
            if (inputIndex == activity.inputIndex) return 0;
            return inputIndex < activity.inputIndex ? -1 : 1;
        }
    }
    @InvocableMethod(label='Prepare a Validated Day Plan' description='Validates and sorts activity rows in Apex, then includes the earliest compatible activities with a sixty-minute gap. No model, messages, or record updates.')
    public static List<Response> prepare(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) return responses;
        for (Request request : requests) responses.add(plan(request == null ? null : request.activities));
        return responses;
    }
    private static Response plan(String input) {
        Response response = new Response(); response.valid = false;
        if (String.isBlank(input) || input.length() > 12000) {
            response.scheduleText = 'Provide up to thirty activity rows using HH:MM|duration minutes|activity name|location.';
            return response;
        }
        List<String> rows = input.replace('\r\n', '\n').replace('\r', '\n').split('\n');
        if (rows.size() > 30) {
            response.scheduleText = 'Provide no more than thirty activity rows.';
            return response;
        }
        List<Activity> activities = new List<Activity>();
        for (Integer index = 0; index < rows.size(); index++) {
            if (String.isBlank(rows[index])) continue;
            List<String> fields = rows[index].split('\\|', -1);
            if (fields.size() != 4 || !Pattern.matches('[0-9]{2}:[0-9]{2}', fields[0].trim())
                || !Pattern.matches('[0-9]{1,3}', fields[1].trim())
                || String.isBlank(fields[2]) || String.isBlank(fields[3])) {
                response.scheduleText = 'An activity row is invalid. Use HH:MM|duration minutes|activity name|location for every row.';
                return response;
            }
            Integer hour = Integer.valueOf(fields[0].trim().substring(0, 2));
            Integer minute = Integer.valueOf(fields[0].trim().substring(3, 5));
            Integer duration = Integer.valueOf(fields[1].trim());
            if (hour > 23 || minute > 59 || duration < 1 || duration > 480 || hour * 60 + minute + duration > 1440
                || fields[2].trim().length() > 100 || fields[3].trim().length() > 100) {
                response.scheduleText = 'An activity time, duration, name, or location is outside the supported range. Check all activity rows.';
                return response;
            }
            Activity activity = new Activity(); activity.startMinute = hour * 60 + minute;
            activity.duration = duration; activity.inputIndex = index;
            activity.name = fields[2].trim(); activity.location = fields[3].trim();
            activities.add(activity);
        }
        if (activities.isEmpty()) {
            response.scheduleText = 'Provide at least one activity row.';
            return response;
        }
        activities.sort();
        List<String> selected = new List<String>(); List<String> skipped = new List<String>();
        Integer priorEnd;
        for (Activity activity : activities) {
            if (priorEnd == null || activity.startMinute >= priorEnd + 60) {
                selected.add(timeText(activity.startMinute) + '–' + timeText(activity.startMinute + activity.duration)
                    + ' | ' + activity.name + ' | ' + activity.location + ' | ' + activity.duration + ' minutes');
                priorEnd = activity.startMinute + activity.duration;
            } else skipped.add(activity.name);
        }
        response.valid = true;
        response.scheduleText = 'Validated schedule\n' + String.join(selected, '\n');
        if (!skipped.isEmpty()) response.scheduleText += '\nNot included because of overlap or insufficient free time: ' + String.join(skipped, ', ') + '.';
        response.scheduleText += '\nSelection rule: start with the earliest activity, then take the next compatible activity. This is not an optimization for the largest number of activities.';
        return response;
    }
    private static String timeText(Integer minute) {
        Integer hour = minute / 60; Integer remainder = Math.mod(minute, 60);
        return (hour < 10 ? '0' : '') + hour + ':' + (remainder < 10 ? '0' : '') + remainder;
    }
}
