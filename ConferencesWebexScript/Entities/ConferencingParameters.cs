namespace ConferencesWebexScript.Entities
{
    public class ConferencingParameters
    {
        public string Title { get; set; }
        public string Description { get; set; }
        public string TimeZone { get; set; }
        public string Host_mail { get; set; }
        public Guest[] Invitees { get; set; }
    }
}
