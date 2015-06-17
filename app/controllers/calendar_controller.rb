class CalendarController < ApplicationController
  @@season = nil

  def show
    if !current_season.nil?
      @@season = current_season.id
    else
      redirect_to account_seasons_path(current_account)
    end

    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @teams_in_season = Team.where(season_id: @@season)
  end

  def view
    @param = params[:team_name]
    @team = Team.find_by(name: Base64.decode64(params[:team_name]))
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @events_by_date = @team.events.group_by(&:startdate)

    @events_by_date.each do |date, events_on_date_hash| #array of events on that date
      if events_on_date_hash.length > 1 #sort only if there are more than 2 events
        @events_by_date[date] = events_on_date_hash.sort_by { |h| h[:starttime] }
      end
    end

    date_range = Date.today..Date.today+2.weeks
    @events = @team.events.where(startdate: date_range)
    @events = @events.sort_by { |h| h[:starttime]}
  end

  def mail
    Team.where(season_id: @@season).each do |team|
      MemberMailer.schedule_email(team).deliver
    end

    respond_to do |format|
      format.js
    end
  end

  def generate
    @teams= Team.where(season_id: @@season).in_groups(2) #split into two equal arrays
    @venues = current_season.venues
    @start = Date.parse(params[:startdate])
    @stime = params[:starttime]
    @etime = params[:endtime]
    @games_per_week = params[:limit]
    @selected_days = params[:weekdays].map(&:to_i)
    @permitted_weekdays = (@start..@start+1.year).select { |k| @selected_days.include?(k.wday)}
    #convert nil values to strings for insertion later
    @teams_in_season = []
    @teams_in_season.push(@teams[0].map { |e| !e ? 'nil' : e })
    @teams_in_season.push(@teams[1].map { |e| !e ? 'nil' : e })
    @success = nil
    @message = nil
    @total_teams = @teams_in_season[0].count.to_i+@teams_in_season[1].count.to_i
    @event_build_list = []
    @events_queued = 1
    @events_required = ((@total_teams/2)*(@total_teams-1))*2 # vs twice
    catch (:error) do
      for r in 0..((@total_teams/@games_per_week.to_f).ceil)-1 #number of weeks needed
        for g in 0..@games_per_week.to_i-1 #number of days available
          @venue_index = 0
          for t in 0..((@total_teams/2)-1)#iterate through teams in one group to save the matchups
            #team automatically gets a 'bye' they are not versing anyone if team1 or 2 is nil
            if @teams_in_season[0][t] == 'nil' || @teams_in_season[1][t] == 'nil'
              @events_queued += 1
              next
            end
            if @venues[@venue_index].blank?
              @message = 'Not enough venues.'
              throw (:error)
            elsif @events_queued <= @events_required
              @event_build_list.push(current_season.@teams_in_season[0][t].events.build(team1: @teams_in_season[0][t].name, team2: @teams_in_season[1][t].name, startdate: @permitted_weekdays[g+r*(@games_per_week.to_i)], enddate: @permitted_weekdays[g+r*(@games_per_week.to_i)], starttime: @stime, endtime: @etime, location: @venues[@venue_index].name))
              @event_build_list.push(current_season.@teams_in_season[1][t].events.build(team1: @teams_in_season[0][t].name, team2: @teams_in_season[1][t].name, startdate: @permitted_weekdays[g+r*(@games_per_week.to_i)], enddate: @permitted_weekdays[g+r*(@games_per_week.to_i)], starttime: @stime, endtime: @etime, location: @venues[@venue_index].name)) #add the event for the opposing team too
              @venue_index += 1
              @events_queued += 1
            else
              next #sufficient events queued
            end
          end
          #rearrange the arrays after all events are saved for this group organization
          if @total_teams > 2
            @teams_in_season[1].push(@teams_in_season[0].pop) #push the last team of group1 to the end of group2
            @teams_in_season[0].insert(1, @teams_in_season[1].shift) #push the last team of group2 to the second index on group1
          end
        end
      end
      @success = 1
      @event_build_list.each do |e|
        e.save
      end
    end

    respond_to do |format|
      format.js #flash message contains success
    end
  end

  def all #show all events of all teams
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @teams_in_season = Team.where(season_id: @@season)
    @events_by_date = {}
    @events = []

    date_range = Date.today..Date.today+2.weeks
    if !@teams_in_season.empty? #fetch team events only if the season contains teams
      @teams_in_season.each do |team|
        @teamevents = team.events.group_by(&:startdate)
        @teamupcoming = team.events.where(startdate: date_range)
        @events_by_date = @events_by_date.merge(@teamevents){|key,oldval,newval| [*oldval].to_a + [*newval].to_a }
        @events.push(*@teamupcoming)
      end
      @events_by_date.each do |date, events_on_date_hash| #array of events on that date
        if events_on_date_hash.length > 1 #sort only if there are more than 2 events
          @events_by_date[date] = events_on_date_hash.sort_by { |h| h[:starttime] }
        end
      end
      @events = @events.sort_by { |h| h[:starttime]}

      #remove duplicates
      @events = @events.uniq {|event| [event[:team1], event[:team2], event[:startdate]]}
      @events_by_date.each do |date, collection|
        @events_by_date[date] = collection.uniq {|event| [event[:team1], event[:team2], event[:startdate]]}
      end

      respond_to do |format|
        format.js { render action: "calendar" }
      end
    end
  end

  def retrieve #fetch for one team
    @date = params[:date] ? Date.parse(params[:date]) : Date.today

    @team = Team.find_by(name: params[:team_name])
    @@current_team = @team
    @events_by_date = @team.events.group_by(&:startdate)

    @events_by_date.each do |date, events_on_date_hash| #array of events on that date
      if events_on_date_hash.length > 1 #sort only if there are more than 2 events
        @events_by_date[date] = events_on_date_hash.sort_by { |h| h[:starttime] }
      end
    end

    date_range = Date.today..Date.today+2.weeks
    @events = @team.events.where(startdate: date_range)
    @events = @events.sort_by { |h| h[:starttime]}

    respond_to do |format|
      format.js { render action: "calendar" }
    end
  end
end
