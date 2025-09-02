@IsTest
private class WellnessJourneyRewardsBatchTest {
    // --- Utility: create a minimal User
    private static User makeUser(String uname) {
        Profile p = [SELECT Id FROM Profile WHERE Name LIKE 'Standard%' LIMIT 1];

        return new User(
            ProfileId        = p.Id,
            Alias            = uname.left(8),
            Email            = uname,
            Username         = uname,
            LastName         = 'Tester',
            TimeZoneSidKey   = 'Asia/Hong_Kong',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey= 'en_US'
        );
    }

    // --- Compute previous quarter start & end (mirrors batch helper methods)
    private static Date prevQStart() {
        Date today = Date.today();
        Integer year = today.year();
        Integer month = today.month();

        Integer prevQStartMonth = ((month - 1) / 3) * 3 + 1 - 3;
        if (prevQStartMonth <= 0) {
            prevQStartMonth += 12;
            year--;
        }
        return Date.newInstance(year, prevQStartMonth, 1);
    }
    private static Date prevQEnd() {
        Date s = prevQStart();
        return s.addMonths(3).addDays(-1);
    }

    @IsTest
    static void testEligibleUsersAreSentOnce() {
        // Users
        User u1 = makeUser('u1@test.example'); // will be eligible (>=12)
        User u2 = makeUser('u2@test.example'); // will be ineligible (<12)
        insert new List<User>{ u1, u2 };

        // Dates for previous quarter
        Date startDate = prevQStart();
        Date endDate   = prevQEnd();

        // Test data: 12 completed journeys within the quarter for u1 (eligible)
        List<Wellness_Journey__c> journeys = new List<Wellness_Journey__c>();
        for (Integer i = 0; i < 12; i++) {
            journeys.add(new Wellness_Journey__c(
                Name = 'U1 Complete ' + i,
                Status__c = 'Complete',
                Completion_Date__c = startDate.addDays(i),
                OwnerId = u1.Id
            ));
        }

        // 11 completed journeys within the quarter for u2 (ineligible)
        for (Integer i = 0; i < 11; i++) {
            journeys.add(new Wellness_Journey__c(
                Name = 'U2 Complete ' + i,
                Status__c = 'Complete',
                Completion_Date__c = startDate.addDays(i),
                OwnerId = u2.Id
            ));
        }

        // Some noise that should NOT count:
        // - Outside the quarter
        journeys.add(new Wellness_Journey__c(
            Name = 'U1 Outside Quarter',
            Status__c = 'Complete',
            Completion_Date__c = endDate.addDays(5),
            OwnerId = u1.Id
        ));
        // - Not complete
        journeys.add(new Wellness_Journey__c(
            Name = 'U2 Not Complete',
            Status__c = 'In Progress',
            Completion_Date__c = startDate.addDays(2),
            OwnerId = u2.Id
        ));

        insert journeys;

        // Mock the HTTP callout used by RewardsCalloutService
        Test.setMock(HttpCalloutMock.class, new RewardsCalloutServiceMock());

        Test.startTest();
        // Run with a small scope to exercise grouping logic
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        // Assertions: callout happened and payload is correct
        System.assertNotEquals(null, RewardsCalloutServiceMock.lastRequestBody, 'Expected a callout payload.');

        // Deserialize and validate content
        List<Object> payload = (List<Object>) JSON.deserializeUntyped(RewardsCalloutServiceMock.lastRequestBody);
        System.assertEquals(1, payload.size(), 'Only one eligible user (u1) should be sent.');

        Map<String, Object> entry = (Map<String, Object>) payload[0];
        System.assertEquals(u1.Id,       (String) entry.get('userId'));
        // System.assertEquals(u1.Name,     (String) entry.get('fullName'));
        // System.assertEquals(u1.Email,    (String) entry.get('email'));
        // System.assertEquals(u1.Username, (String) entry.get('username'));
    }

    @IsTest
    static void testNoEligibleUsersSendsEmptyArray() {
        // Create a single user with <12 journeys
        User u = makeUser('u3@test.example');
        insert u;

        Date startDate = prevQStart();

        List<Wellness_Journey__c> js = new List<Wellness_Journey__c>();
        for (Integer i = 0; i < 5; i++) {
            js.add(new Wellness_Journey__c(
                Name = 'Few Only ' + i,
                Status__c = 'Complete',
                Completion_Date__c = startDate.addDays(i),
                OwnerId = u.Id
            ));
        }
        insert js;

        Test.setMock(HttpCalloutMock.class, new RewardsCalloutServiceMock());

        Test.startTest();
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        System.assertNotEquals(null, RewardsCalloutServiceMock.lastRequestBody, 'Expected a callout even if empty.');
        List<Object> payload = (List<Object>) JSON.deserializeUntyped(RewardsCalloutServiceMock.lastRequestBody);
        System.assertEquals(0, payload.size(), 'No users should be eligible.');
    }
}