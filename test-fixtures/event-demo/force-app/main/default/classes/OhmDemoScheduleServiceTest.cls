@IsTest
private class OhmDemoScheduleServiceTest {
    private static OhmDemoScheduleService.Request request(String rows) {
        OhmDemoScheduleService.Request request = new OhmDemoScheduleService.Request(); request.activities = rows; return request;
    }
    @IsTest static void sortsAndIncludesExactMinimumGapWhileSkippingOverlap() {
        String input = '13:00|60|Forest walk|Trailhead\n09:00|45|Kayaking|Boathouse\n10:30|30|Clay studio|Art room\n10:45|45|Garden tour|Garden\n09:15|45|Breakfast tasting|Cafe';
        OhmDemoScheduleService.Response result = OhmDemoScheduleService.prepare(new List<OhmDemoScheduleService.Request>{ request(input) })[0];
        System.assertEquals(true, result.valid);
        System.assert(result.scheduleText.contains('09:00–09:45 | Kayaking'));
        System.assert(result.scheduleText.contains('10:45–11:30 | Garden tour'), 'An exact sixty-minute gap is accepted.');
        System.assert(result.scheduleText.indexOf('Garden tour') < result.scheduleText.indexOf('Forest walk'));
        System.assert(!result.scheduleText.contains('10:30–11:00'), 'A forty-five-minute gap is rejected.');
        System.assert(!result.scheduleText.contains('09:15–10:00'), 'An overlapping activity is rejected.');
        System.assert(result.scheduleText.contains('Breakfast tasting, Clay studio'));
    }
    @IsTest static void rejectsMalformedRowsWithoutInventingPartialSchedule() {
        for (String input : new List<String>{'09:00|45|Valid|Pier\n25:00|30|Invalid|Hall', '09:00|0|Invalid|Hall', '23:30|60|Invalid|Hall', '09:00|45|Name|', 'not an activity'}) {
            OhmDemoScheduleService.Response result = OhmDemoScheduleService.prepare(new List<OhmDemoScheduleService.Request>{request(input)})[0];
            System.assertEquals(false, result.valid);
            System.assert(!result.scheduleText.contains('Validated schedule'));
        }
    }
    @IsTest static void processesEveryBulkRequestIndependentlyAndKeepsTieOrder() {
        List<OhmDemoScheduleService.Response> results = OhmDemoScheduleService.prepare(new List<OhmDemoScheduleService.Request>{
            request('09:00|30|First|Studio\n09:00|30|Second|Studio'), request(''), null,
            request('14:00|60|Afternoon walk|Forest')
        });
        System.assertEquals(4, results.size());
        System.assertEquals(true, results[0].valid);
        System.assert(results[0].scheduleText.contains('09:00–09:30 | First'));
        System.assert(results[0].scheduleText.contains('free time: Second.'));
        System.assertEquals(false, results[1].valid);
        System.assertEquals(false, results[2].valid);
        System.assertEquals(true, results[3].valid);
        System.assertEquals(0, OhmDemoScheduleService.prepare(null).size());
    }
    @IsTest static void boundsInputAndAcceptsWindowsNewlines() {
        String input = '';
        for (Integer index = 0; index < 31; index++) input += '09:00|30|Activity|Hall\n';
        System.assertEquals(false, OhmDemoScheduleService.prepare(new List<OhmDemoScheduleService.Request>{request(input)})[0].valid);
        System.assertEquals(true, OhmDemoScheduleService.prepare(new List<OhmDemoScheduleService.Request>{request('09:00|30|One|Hall\r\n11:00|30|Two|Pier')})[0].valid);
    }
}
