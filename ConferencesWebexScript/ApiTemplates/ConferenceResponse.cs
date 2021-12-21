using System;

namespace ConferencesWebexScript.ApiTemplates
{
    internal class ConferenceResponse
    {
        public string id { get; set; }
        public string title { get; set; }
        public string state { get; set; }
        public string timezone { get; set; }
        public DateTime start { get; set; }
        public DateTime end { get; set; }
        public string hostDisplayName { get; set; }
        public string siteUrl { get; set; }
        public Uri webLink { get; set; }
        public string sipAddress { get; set; }
    }

}
